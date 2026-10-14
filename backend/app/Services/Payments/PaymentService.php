<?php

namespace App\Services\Payments;

use App\Enums\DeliveryStatus;
use App\Enums\PaymentMethod;
use App\Enums\PaymentStatus;
use App\Models\Delivery;
use App\Models\Media;
use App\Models\Payment;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Paiement Flooz / Mixx by Yas sans agrégateur : le client vire sur le numéro marchand et envoie
 * une capture d'écran, que l'admin vérifie. L'admin peut aussi valider directement (espèces, etc.).
 *
 * Chaque opération verrouille la livraison et recontrôle son état : deux clics (ou deux admins)
 * simultanés ne peuvent pas valider / refuser deux fois.
 */
class PaymentService
{
    /** Preuve envoyée depuis l'app : capture stockée en base (le disque Render est éphémère). */
    public function submitProof(Delivery $delivery, PaymentMethod $method, string $reference, string $payerPhone, UploadedFile $screenshot): Payment
    {
        $reference = Payment::normalizeReference($reference);
        if ($reference === null) {
            throw ValidationException::withMessages(['transaction_ref' => 'Indiquez la référence de la transaction.']);
        }

        return DB::transaction(function () use ($delivery, $method, $reference, $payerPhone, $screenshot) {
            $fresh = $delivery->lockFresh();
            if (! $fresh->canSubmitPayment()) {
                throw ValidationException::withMessages(['payment' => 'Un paiement est déjà en cours de vérification ou confirmé.']);
            }
            if (Payment::referenceInUse($method, $reference)) {
                throw ValidationException::withMessages(['transaction_ref' => 'Cette référence de transaction a déjà été utilisée.']);
            }

            $payment = $fresh->payments()->create([
                'method' => $method,
                'transaction_ref' => $reference,
                'payer_phone' => $payerPhone,
                'amount' => $fresh->total_amount,
                'screenshot_media_id' => Media::fromUpload($screenshot)->id,
                'status' => PaymentStatus::Submitted,
            ]);
            $fresh->forceFill(['payment_status' => PaymentStatus::Submitted])->save();

            return $payment;
        });
    }

    /**
     * Validation par l'admin sans passer par l'app (espèces, virement vérifié à la main).
     * Crée une trace de paiement confirmée et débloque l'assignation du livreur.
     */
    public function confirmByAdmin(Delivery $delivery, User $admin, PaymentMethod $method, ?string $reference): Payment
    {
        $reference = Payment::normalizeReference($reference);

        return DB::transaction(function () use ($delivery, $admin, $method, $reference) {
            $fresh = $delivery->lockFresh();
            if ($fresh->status === DeliveryStatus::Cancelled || $fresh->payment_status === PaymentStatus::Verified) {
                throw ValidationException::withMessages(['payment' => 'Livraison annulée ou déjà payée.']);
            }
            if ($reference !== null && Payment::referenceInUse($method, $reference)) {
                throw ValidationException::withMessages(['reference' => 'Cette référence de transaction a déjà été utilisée.']);
            }

            // Les preuves encore en attente sont closes : c'est l'admin qui tranche.
            $fresh->payments()->whereIn('status', [PaymentStatus::Pending, PaymentStatus::Submitted])
                ->update(['status' => PaymentStatus::Rejected, 'rejection_reason' => 'Remplacé par une validation manuelle']);

            $payment = $fresh->payments()->create([
                'method' => $method,
                'transaction_ref' => $reference,
                'payer_phone' => $fresh->client->phone_number,
                'amount' => $fresh->total_amount,
                'status' => PaymentStatus::Verified,
                'reviewed_by' => $admin->id,
                'reviewed_at' => now(),
            ]);
            $fresh->forceFill(['payment_status' => PaymentStatus::Verified])->save();
            $delivery->setRawAttributes($fresh->getAttributes(), true);

            return $payment;
        });
    }

    /** Preuve jugée valable : la livraison est payée (refusé si elle a été annulée entre-temps). */
    public function approve(Payment $payment, User $admin): Delivery
    {
        return DB::transaction(function () use ($payment, $admin) {
            $delivery = Delivery::whereKey($payment->delivery_id)->lockForUpdate()->firstOrFail();
            $payment = Payment::whereKey($payment->id)->lockForUpdate()->firstOrFail();

            if ($payment->status !== PaymentStatus::Submitted) {
                throw ValidationException::withMessages(['payment' => 'Ce paiement a déjà été traité.']);
            }
            if ($delivery->status === DeliveryStatus::Cancelled) {
                throw ValidationException::withMessages(['payment' => 'Livraison annulée : le paiement ne peut pas être confirmé (rembourser le client si nécessaire).']);
            }
            if ($delivery->payment_status === PaymentStatus::Verified) {
                throw ValidationException::withMessages(['payment' => 'Cette livraison est déjà payée : refusez cette preuve en double.']);
            }

            $payment->forceFill([
                'status' => PaymentStatus::Verified,
                'reviewed_by' => $admin->id,
                'reviewed_at' => now(),
            ])->save();
            $delivery->forceFill(['payment_status' => PaymentStatus::Verified])->save();

            return $delivery;
        });
    }

    /**
     * Preuve refusée. La livraison ne repasse « refusée » que si elle attendait cette preuve :
     * refuser un doublon ne touche jamais une livraison déjà payée.
     *
     * @return bool true si le client doit renvoyer une preuve
     */
    public function reject(Payment $payment, User $admin, string $reason): bool
    {
        return DB::transaction(function () use ($payment, $admin, $reason) {
            $delivery = Delivery::whereKey($payment->delivery_id)->lockForUpdate()->firstOrFail();
            $payment = Payment::whereKey($payment->id)->lockForUpdate()->firstOrFail();

            if ($payment->status !== PaymentStatus::Submitted) {
                throw ValidationException::withMessages(['payment' => 'Ce paiement a déjà été traité.']);
            }

            $payment->forceFill([
                'status' => PaymentStatus::Rejected,
                'reviewed_by' => $admin->id,
                'reviewed_at' => now(),
                'rejection_reason' => $reason,
            ])->save();

            if ($delivery->payment_status !== PaymentStatus::Submitted) {
                return false;
            }
            $delivery->forceFill(['payment_status' => PaymentStatus::Rejected])->save();

            return $delivery->status !== DeliveryStatus::Cancelled;
        });
    }
}
