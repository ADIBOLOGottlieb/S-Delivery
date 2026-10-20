<?php

namespace App\Http\Controllers\Api;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\User;
use App\Support\Identifier;
use App\Support\Phone;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\Rules\Password;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    private const MAX_LOGIN_ATTEMPTS = 5;

    private const LOGIN_LOCK_SECONDS = 15 * 60;

    /** Même clé pour toutes les écritures d'un numéro (ou d'un email). */
    private static function loginThrottleKey(string $login): string
    {
        return 'login:'.sha1(Identifier::login($login));
    }

    /** Inscription publique : uniquement des comptes clients. Les livreurs sont créés par l'admin. */
    public function register(Request $request): JsonResponse
    {
        // Email enregistré en minuscules : unicité et connexion insensibles à la casse.
        if (is_string($request->input('email'))) {
            $request->merge(['email' => Identifier::email($request->input('email'))]);
        }

        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['nullable', 'email', 'max:255', Identifier::uniqueEmail()],
            'phone_number' => ['required', 'string', 'max:30'],
            'password' => ['required', 'confirmed', Password::min(8)],
        ]);

        // Numéro enregistré sous une seule forme ; un ancien client déjà créé par l'agence est redirigé.
        $data['phone_number'] = Phone::normalize($data['phone_number']);
        if (User::whereIn('phone_number', Phone::variants($data['phone_number']))->exists()) {
            throw ValidationException::withMessages([
                'phone_number' => "Ce numéro a déjà un compte S-Delivery. Connectez-vous avec l'identifiant reçu de l'agence.",
            ]);
        }

        $user = User::create([...$data, 'role' => Role::Client]);

        return response()->json([
            'token' => $user->createToken('mobile')->plainTextToken,
            'user' => new UserResource($user),
        ], 201);
    }

    /** Connexion par email ou numéro de téléphone. */
    public function login(Request $request): JsonResponse
    {
        $data = $request->validate([
            'login' => ['required', 'string'],
            'password' => ['required', 'string'],
        ]);

        // Échecs comptés par compte visé (en plus du throttle par IP) : bloque le test de mots de passe.
        $key = self::loginThrottleKey($data['login']);
        if (RateLimiter::tooManyAttempts($key, self::MAX_LOGIN_ATTEMPTS)) {
            $minutes = (int) ceil(RateLimiter::availableIn($key) / 60);
            throw ValidationException::withMessages([
                'login' => "Trop de tentatives de connexion. Réessayez dans {$minutes} minute".($minutes > 1 ? 's' : '').'.',
            ])->status(429);
        }

        // Le numéro est accepté sous toutes ses écritures (90 11 22 33, 22890112233, +228…), l'email sans casse.
        $user = Identifier::findUser($data['login']);

        if (! $user || ! Hash::check($data['password'], $user->password)) {
            RateLimiter::hit($key, self::LOGIN_LOCK_SECONDS);
            throw ValidationException::withMessages(['login' => 'Identifiants incorrects.']);
        }
        RateLimiter::clear($key);

        if (! $user->is_active) {
            throw ValidationException::withMessages(['login' => "Ce compte a été désactivé. Contactez l'agence."]);
        }

        if ($user->isAdmin()) {
            throw ValidationException::withMessages(['login' => "Les administrateurs utilisent le panneau d'administration web."]);
        }

        return response()->json([
            'token' => $user->createToken('mobile')->plainTextToken,
            'user' => new UserResource($user),
        ]);
    }

    public function me(Request $request): UserResource
    {
        return new UserResource($request->user());
    }

    /** Jeton Firebase de l'appareil, pour les notifications push (rappels livreur, promos). */
    public function deviceToken(Request $request): JsonResponse
    {
        $token = $request->validate(['token' => ['required', 'string', 'max:500']])['token'];

        // Un appareil n'appartient qu'à un compte à la fois.
        User::where('fcm_token', $token)->whereKeyNot($request->user()->id)->update(['fcm_token' => null]);
        $request->user()->forceFill(['fcm_token' => $token])->save();

        return response()->json(['message' => 'Appareil enregistré.']);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->forceFill(['fcm_token' => null])->save();
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'Déconnecté.']);
    }
}
