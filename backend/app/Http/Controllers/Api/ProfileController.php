<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\Media;
use App\Models\User;
use App\Support\Phone;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;
use Illuminate\Validation\ValidationException;
use Laravel\Sanctum\PersonalAccessToken;

/** Photo de profil (client et livreur). */
class ProfileController extends Controller
{
    public function updateAvatar(Request $request): UserResource
    {
        $request->validate(['photo' => ['required', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120']]);

        $user = $request->user();
        $previous = $user->avatar_media_id;

        $user->forceFill(['avatar_media_id' => Media::fromUpload($request->file('photo'))->id])->save();
        if ($previous) {
            Media::whereKey($previous)->delete();
        }

        return new UserResource($user->refresh());
    }

    /**
     * Identifiants de connexion (reçus de l'agence ou choisis à l'inscription) : nouveau mot de passe,
     * numéro et/ou email. Le mot de passe actuel est toujours exigé.
     */
    public function updateCredentials(Request $request): UserResource
    {
        $user = $request->user();
        $data = $request->validate([
            'current_password' => ['required', 'current_password:sanctum'],
            'phone_number' => ['sometimes', 'required', 'string', 'max:30'],
            'email' => ['sometimes', 'nullable', 'email', 'max:255', Rule::unique('users')->ignore($user)],
            'password' => ['sometimes', 'required', 'confirmed', Password::min(8)],
        ], [
            'current_password.current_password' => 'Mot de passe actuel incorrect.',
        ]);

        if (isset($data['phone_number'])) {
            $phone = Phone::normalize($data['phone_number']);
            if (! Phone::isValid($phone)) {
                throw ValidationException::withMessages(['phone_number' => 'Numéro invalide.']);
            }
            $taken = User::whereIn('phone_number', Phone::variants($phone))->whereKeyNot($user->id)->exists();
            if ($taken) {
                throw ValidationException::withMessages(['phone_number' => 'Ce numéro est déjà utilisé par un autre compte.']);
            }
            $user->phone_number = $phone;
        }
        if (array_key_exists('email', $data)) {
            $user->email = $data['email'];
        }
        if (isset($data['password'])) {
            $user->password = $data['password'];
        }
        $user->save();

        // Mot de passe changé : les autres appareils sont déconnectés, celui-ci reste connecté.
        if (isset($data['password'])) {
            $current = $user->currentAccessToken();
            $user->tokens()
                ->when($current instanceof PersonalAccessToken, fn ($q) => $q->whereKeyNot($current->getKey()))
                ->delete();
        }

        return new UserResource($user->refresh());
    }

    public function deleteAvatar(Request $request): UserResource
    {
        $user = $request->user();
        $previous = $user->avatar_media_id;

        $user->forceFill(['avatar_media_id' => null])->save();
        if ($previous) {
            Media::whereKey($previous)->delete();
        }

        return new UserResource($user->refresh());
    }
}
