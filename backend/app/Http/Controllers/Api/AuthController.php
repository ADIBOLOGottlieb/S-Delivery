<?php

namespace App\Http\Controllers\Api;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\User;
use App\Support\Phone;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    /** Inscription publique : uniquement des comptes clients. Les livreurs sont créés par l'admin. */
    public function register(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['nullable', 'email', 'max:255', 'unique:users,email'],
            'phone_number' => ['required', 'string', 'max:30'],
            'password' => ['required', 'confirmed', Password::min(8)],
        ]);

        // Numéro enregistré sous une seule forme ; un ancien client déjà créé par l'agence est redirigé.
        $data['phone_number'] = Phone::normalize($data['phone_number']);
        if (User::whereIn('phone_number', Phone::variants($data['phone_number']))->exists()) {
            throw ValidationException::withMessages([
                'phone_number' => "Ce numéro a déjà un compte VOOM. Connectez-vous avec l'identifiant reçu de l'agence.",
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

        // Le numéro est accepté sous toutes ses écritures (90 11 22 33, 22890112233, +228…).
        $user = User::query()
            ->where('email', $data['login'])
            ->orWhereIn('phone_number', Phone::variants($data['login']))
            ->first();

        if (! $user || ! Hash::check($data['password'], $user->password)) {
            throw ValidationException::withMessages(['login' => 'Identifiants incorrects.']);
        }

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
