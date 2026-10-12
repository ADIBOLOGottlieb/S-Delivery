<?php

namespace App\Services\Payments;

use App\Enums\DeliveryStatus;
use App\Enums\PaymentMethod;
use App\Enums\PaymentStatus;
use App\Models\Delivery;
use App\Models\Payment;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Paiement Flooz / Mixx by Yas sans agrégateur : le client vire sur le numéro marchand et envoie
 * une capture d'écran, que l'admin vérifie. L'admin peut aussi valider directement (espèces, etc.).
 */
class PaymentService
{
    /**
     * Validation par l'admin sans passer par l'app (espèces, virement vérifié à la main).
     * Crée une trace de paiement confirmée et débloque l'assignation du livreur.
     */
    public function confirmByAdmin(Delivery $delivery, User $admin, PaymentMethod $method, ?string $reference): Payment
    {
        if ($delivery->status === DeliveryStatus::Cancelled || $delivery->payment_status === PaymentStatus::Verified) {
            throw ValidationException::withMessages(['payment' => 'Livraison annulée ou déjà payée.']);
        }

        return DB::transaction(function () use ($delivery, $admin, $method, $reference) {
            // Les preuves encore en attente sont closes : c'est l'admin qui tranche.
            $delivery->payments()->whereIn('status', [PaymentStatus::Pending, PaymentStatus::Submitted])
                ->update(['status' => PaymentStatus::Rejected, 'rejection_reason' => 'Remplacé par une validation manuelle']);

            $payment = $delivery->payments()->create([
                'method' => $method,
                'transaction_ref' => $reference,
                'payer_phone' => $delivery->client->phone_number,
                'amount' => $delivery->total_amount,
                'status' => PaymentStatus::Verified,
                'reviewed_by' => $admin->id,
                'reviewed_at' => now(),
            ]);
            $delivery->forceFill(['payment_status' => PaymentStatus::Verified])->save();

            return $payment;
        });
    }
}
