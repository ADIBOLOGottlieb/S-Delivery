<?php

namespace App\Http\Controllers\Api;

use App\Enums\DeliveryStatus;
use App\Enums\PaymentStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\DeliveryRequest;
use App\Models\Media;
use App\Models\User;
use App\Support\Identifier;
use App\Support\Phone;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\Rules\Password;
use Illuminate\Validation\ValidationException;
use Laravel\Sanctum\PersonalAccessToken;

/** Profil (client et livreur) : photo, identifiants, suppression du compte. */
class ProfileController extends Controller
{
    /**
     * Suppression du compte (exigence Google Play) : les données personnelles sont anonymisées,
     * l'historique des livraisons et paiements est conservé pour la comptabilité.
     */
    public function deleteAccount(Request $request): JsonResponse
    {
        $user = $request->user();
        $request->validate(['password' => ['required', 'string', 'current_password:sanctum']], [
            'password.required' => 'Saisissez votre mot de passe pour confirmer la suppression.',
            'password.current_password' => 'Mot de passe incorrect.',
        ]);

        if ($user->isAdmin()) {
            abort(403, 'Un compte administrateur ne peut pas être supprimé depuis l\'application.');
        }

        DB::transaction(function () use ($user) {
            $user = User::whereKey($user->id)->lockForUpdate()->firstOrFail();

            if ($this->hasActiveDelivery($user)) {
                throw ValidationException::withMessages([
                    'account' => 'Une livraison est en cours (payée ou en route) : attendez qu\'elle soit terminée, '
                        ."ou contactez l'agence, avant de supprimer votre compte.",
                ]);
            }

            // Livraisons jamais payées : annulées. Discussions : clôturées.
            $user->deliveries()
                ->where('status', DeliveryStatus::Pending)
                ->whereIn('payment_status', [PaymentStatus::Unpaid, PaymentStatus::Rejected, PaymentStatus::Failed])
                ->update(['status' => DeliveryStatus::Cancelled, 'cancelled_at' => now(), 'cancel_reason' => 'Compte supprimé par le client']);
            $user->deliveryRequests()->where('status', '!=', DeliveryRequest::CLOSED)->update(['status' => DeliveryRequest::CLOSED]);

            if ($user->email) {
                DB::table('password_reset_tokens')->where('email', $user->email)->delete();
            }
            $avatar = $user->avatar_media_id;
            $user->tokens()->delete();

            // Valeurs uniques qui ne sont ni un numéro ni un email utilisables : personne ne peut s'y connecter.
            $tag = 'supprime-'.$user->id.'-'.Str::lower(Str::random(8));
            $user->forceFill([
                'name' => 'Compte supprimé',
                'phone_number' => $tag,
                'email' => $tag.'@compte-supprime.invalid',
                'district' => null,
                'vehicle' => null,
                'password' => Str::random(64),
                'remember_token' => null,
                'fcm_token' => null,
                'avatar_media_id' => null,
                'email_verified_at' => null,
                'is_active' => false,
                'anonymized_at' => now(),
            ])->save();

            if ($avatar) {
                Media::whereKey($avatar)->delete();
            }
        });

        return response()->json(['message' => 'Votre compte a été supprimé. Merci d\'avoir utilisé VOOM Delivery.']);
    }

    /** Livraison payée (ou en vérification) pas encore livrée, ou course en cours pour un livreur. */
    private function hasActiveDelivery(User $user): bool
    {
        $inProgress = [DeliveryStatus::Assigned, DeliveryStatus::PickedUp];

        return $user->deliveries()
            ->where(fn ($q) => $q
                ->whereIn('status', $inProgress)
                ->orWhere(fn ($q) => $q
                    ->where('status', DeliveryStatus::Pending)
                    ->whereIn('payment_status', [PaymentStatus::Pending, PaymentStatus::Submitted, PaymentStatus::Verified])))
            ->exists()
            || $user->assignedDeliveries()->whereIn('status', $inProgress)->exists();
    }

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
        // Email enregistré en minuscules : unicité et connexion insensibles à la casse.
        if (is_string($request->input('email'))) {
            $request->merge(['email' => Identifier::email($request->input('email'))]);
        }
        $data = $request->validate([
            'current_password' => ['required', 'current_password:sanctum'],
            'phone_number' => ['sometimes', 'required', 'string', 'max:30'],
            'email' => ['sometimes', 'nullable', 'email', 'max:255', Identifier::uniqueEmail($user->id)],
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
            $user->email = Identifier::email($data['email']);
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
