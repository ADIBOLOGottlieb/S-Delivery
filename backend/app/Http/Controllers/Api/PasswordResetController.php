<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\User;
use App\Support\Phone;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\Rules\Password;
use Illuminate\Validation\ValidationException;

/**
 * Mot de passe oublié, sans intervention de l'agence : un code à 6 chiffres est envoyé
 * à l'email du compte (envoi gratuit via un service SMTP comme Brevo), puis le client
 * choisit un nouveau mot de passe et se retrouve connecté.
 */
class PasswordResetController extends Controller
{
    private const CODE_MINUTES = 15;

    private const MAX_ATTEMPTS = 5;

    public function forgot(Request $request): JsonResponse
    {
        $login = $request->validate(['login' => ['required', 'string', 'max:255']])['login'];
        $user = $this->findUser($login);

        if (! $user || ! $user->is_active) {
            throw ValidationException::withMessages(['login' => 'Aucun compte actif avec cet email ou ce numéro.']);
        }
        if (! $user->email) {
            throw ValidationException::withMessages([
                'login' => "Aucun email n'est enregistré sur ce compte : contactez l'agence pour un nouveau mot de passe. "
                    .'Pensez ensuite à ajouter votre email dans Profil › Mes identifiants.',
            ]);
        }

        $code = str_pad((string) random_int(0, 999_999), 6, '0', STR_PAD_LEFT);
        DB::table('password_reset_tokens')->updateOrInsert(
            ['email' => $user->email],
            ['token' => Hash::make($code), 'created_at' => now()],
        );
        RateLimiter::clear($this->attemptsKey($user));

        try {
            Mail::raw(
                "Bonjour {$user->name},\n\nVotre code VOOM Delivery pour choisir un nouveau mot de passe : {$code}\n\n"
                .'Il est valable '.self::CODE_MINUTES." minutes. Si vous n'avez rien demandé, ignorez ce message.",
                fn ($message) => $message->to($user->email)->subject("Votre code VOOM Delivery : {$code}"),
            );
        } catch (\Throwable $e) {
            Log::error('Envoi du code de réinitialisation impossible', ['user' => $user->id, 'error' => $e->getMessage()]);
            throw ValidationException::withMessages(['login' => "L'email n'a pas pu être envoyé. Réessayez dans quelques minutes."]);
        }

        return response()->json([
            'message' => 'Code envoyé.',
            'email' => $this->mask($user->email),
            'expires_in_minutes' => self::CODE_MINUTES,
        ]);
    }

    public function reset(Request $request): JsonResponse
    {
        $data = $request->validate([
            'login' => ['required', 'string', 'max:255'],
            'code' => ['required', 'string', 'max:10'],
            'password' => ['required', 'confirmed', Password::min(8)],
        ]);

        $user = $this->findUser($data['login']);
        $row = $user?->email ? DB::table('password_reset_tokens')->where('email', $user->email)->first() : null;
        $invalid = fn () => ValidationException::withMessages(['code' => 'Code incorrect ou expiré. Demandez un nouveau code.']);

        if (! $user || ! $row || now()->subMinutes(self::CODE_MINUTES)->gt($row->created_at)) {
            throw $invalid();
        }

        // Au-delà de 5 essais, le code est détruit : il faut en redemander un.
        $key = $this->attemptsKey($user);
        if (RateLimiter::tooManyAttempts($key, self::MAX_ATTEMPTS)) {
            DB::table('password_reset_tokens')->where('email', $user->email)->delete();
            throw $invalid();
        }
        if (! Hash::check(trim($data['code']), $row->token)) {
            RateLimiter::hit($key, self::CODE_MINUTES * 60);
            throw $invalid();
        }

        DB::transaction(function () use ($user, $data) {
            $user->forceFill(['password' => $data['password']])->save();
            $user->tokens()->delete(); // les autres appareils sont déconnectés
            DB::table('password_reset_tokens')->where('email', $user->email)->delete();
        });
        RateLimiter::clear($key);

        return response()->json([
            'token' => $user->createToken('mobile')->plainTextToken,
            'user' => new UserResource($user),
        ]);
    }

    private function findUser(string $login): ?User
    {
        $login = trim($login);

        return User::where('email', $login)->orWhereIn('phone_number', Phone::variants($login))->first();
    }

    private function attemptsKey(User $user): string
    {
        return 'password-reset:'.$user->id;
    }

    /** « a****@gmail.com » : le client reconnaît son email sans qu'il soit dévoilé. */
    private function mask(string $email): string
    {
        [$name, $domain] = array_pad(explode('@', $email, 2), 2, '');

        return mb_substr($name, 0, 1).str_repeat('*', max(mb_strlen($name) - 1, 3)).'@'.$domain;
    }
}
