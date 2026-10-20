<?php

namespace App\Services\Payments;

use App\Enums\DeliveryStatus;
use App\Enums\PaymentMethod;
use App\Enums\PaymentStatus;
use App\Models\Delivery;
use App\Models\Media;
use App\Models\Payment;
use App\Models\Setting;
use App\Models\User;
use App\Services\DeliveryReminder;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Paiements d'une livraison :
 * - en ligne (KKiaPay, PayGate) : le client paie dans l'app, la confirmation est automatique
 *   après revérification auprès de l'agrégateur ;
 * - manuel : virement au numéro marchand + capture d'écran vérifiée par l'admin ;
 * - validation directe par l'admin (espèces, virement vérifié à la main).
 *
 * Chaque opération verrouille la livraison et recontrôle son état : deux clics (ou deux admins,
 * ou un webhook et l'app) simultanés ne peuvent pas valider deux fois.
 */
class PaymentService
{
    /** Au-delà, une tentative sans réponse de l'agrégateur est abandonnée. */
    private const PENDING_TIMEOUT_MINUTES = 30;

    /** Une tentative plus récente bloque la création d'une nouvelle (double débit). */
    private const RECENT_PENDING_MINUTES = 3;

    // --- Paiement en ligne -----------------------------------------------------------------------

    /** Mode choisi dans Admin › Réglages : auto, manual ou simulation. */
    public function mode(): string
    {
        return Setting::get('payment_mode') ?: 'auto';
    }

    public function gateway(): ?PaymentGateway
    {
        return match ($this->mode()) {
            'simulation' => app(SimulationGateway::class),
            'manual' => null,
            default => $this->configuredGateway(),
        };
    }

    /** Agrégateur réel défini dans .env (PAYMENT_GATEWAY), s'il a ses clés. */
    public function configuredGateway(): ?PaymentGateway
    {
        $gateway = match (config('payments.gateway')) {
            'kkiapay' => app(KkiapayGateway::class),
            'paygate' => app(PaygateGateway::class),
            default => null,
        };

        return $gateway?->isConfigured() ? $gateway : null;
    }

    /** Paiement en ligne actif ? Sinon l'app propose le virement + capture d'écran. */
    public function enabled(): bool
    {
        return $this->gateway() !== null;
    }

    /**
     * Démarre un paiement en ligne.
     *
     * @return array{payment: Payment, mode: string, message: string, redirect_url?: string}
     */
    public function checkout(Delivery $delivery, PaymentMethod $method, string $phone): array
    {
        $gateway = $this->gateway() ?? throw ValidationException::withMessages([
            'payment' => "Le paiement en ligne n'est pas activé. Payez par virement puis envoyez la capture d'écran.",
        ]);
        if (! in_array($method, $gateway->methods(), true)) {
            throw ValidationException::withMessages(['method' => "Ce moyen de paiement n'est pas disponible."]);
        }

        // Tentatives précédentes : un paiement validé entre-temps ne doit pas être redemandé.
        foreach ($delivery->payments()->where('status', PaymentStatus::Pending)->get() as $pending) {
            $this->refresh($pending);
            if ($pending->status === PaymentStatus::Pending && $pending->created_at->gt(now()->subMinutes(self::RECENT_PENDING_MINUTES))) {
                throw ValidationException::withMessages([
                    'payment' => 'Un paiement est déjà en cours : validez-le sur votre téléphone ou réessayez dans quelques minutes.',
                ]);
            }
            if ($pending->status === PaymentStatus::Pending) {
                $pending->forceFill(['status' => PaymentStatus::Failed])->save();
            }
        }

        $payment = DB::transaction(function () use ($delivery, $gateway, $method, $phone) {
            $fresh = $delivery->lockFresh();
            if (! $fresh->canSubmitPayment()) {
                throw ValidationException::withMessages(['payment' => 'Cette livraison est déjà payée ou ne peut plus être payée.']);
            }

            return $fresh->payments()->create([
                'method' => $method,
                'gateway' => $gateway->name(),
                'checkout_token' => (string) Str::uuid(),
                'payer_phone' => $phone,
                'amount' => $fresh->total_amount,
                'status' => PaymentStatus::Pending,
            ]);
        });

        try {
            $result = $gateway->start($payment);
        } catch (ValidationException $e) {
            $payment->forceFill(['status' => PaymentStatus::Failed])->save();
            throw $e;
        }

        return ['payment' => $payment, ...$result];
    }

    /** Vérifie une tentative en attente auprès de l'agrégateur et applique le résultat. */
    public function refresh(Payment $payment): Payment
    {
        if ($payment->status !== PaymentStatus::Pending || ! $payment->isGateway()) {
            return $payment;
        }

        $gateway = match ($payment->gateway) {
            'kkiapay' => app(KkiapayGateway::class),
            'paygate' => app(PaygateGateway::class),
            'simulation' => app(SimulationGateway::class),
            default => null,
        };

        $paid = $gateway?->check($payment);

        if ($paid === true) {
            $this->markPaid($payment);
        } elseif ($paid === false || $payment->created_at->lt(now()->subMinutes(self::PENDING_TIMEOUT_MINUTES))) {
            $payment->forceFill(['status' => PaymentStatus::Failed])->save();
        }

        return $payment->refresh();
    }

    /** KKiaPay : rattache l'identifiant de transaction renvoyé par le widget ou le webhook. */
    public function attachReference(Payment $payment, string $transactionId): void
    {
        if ($payment->gateway_reference || $payment->status !== PaymentStatus::Pending) {
            return;
        }

        // Une même transaction ne peut pas payer deux livraisons.
        $usedElsewhere = Payment::where('gateway', $payment->gateway)
            ->where('gateway_reference', $transactionId)
            ->whereKeyNot($payment->id)
            ->exists();

        if (! $usedElsewhere) {
            $payment->forceFill(['gateway_reference' => $transactionId])->save();
        }
    }

    /** Résultat choisi sur la page de simulation (refusé hors mode simulation). */
    public function simulate(Payment $payment, bool $success): void
    {
        if ($payment->gateway !== 'simulation' || $payment->status !== PaymentStatus::Pending || $this->mode() !== 'simulation') {
            return;
        }

        $success
            ? $this->markPaid($payment)
            : $payment->forceFill(['status' => PaymentStatus::Failed])->save();
    }

    /**
     * Paiement confirmé par l'agrégateur, sous verrou : la tentative n'est validée qu'une fois.
     * Livraison annulée entre-temps : l'argent est encaissé, elle apparaît « à rembourser » dans l'admin.
     */
    private function markPaid(Payment $payment): void
    {
        $delivery = DB::transaction(function () use ($payment) {
            $delivery = Delivery::whereKey($payment->delivery_id)->lockForUpdate()->firstOrFail();
            $fresh = Payment::whereKey($payment->id)->lockForUpdate()->firstOrFail();
            if ($fresh->status !== PaymentStatus::Pending) {
                return null;
            }

            $fresh->forceFill(['status' => PaymentStatus::Verified, 'reviewed_at' => now()])->save();
            if ($delivery->payment_status === PaymentStatus::Verified) {
                return null; // déjà payée autrement : l'agence rembourse le doublon
            }
            $delivery->forceFill(['payment_status' => PaymentStatus::Verified])->save();

            return $delivery;
        });

        if ($delivery && $delivery->status !== DeliveryStatus::Cancelled) {
            app(DeliveryReminder::class)->notifyClient($delivery->load('client'), 'payment_verified');
        }
    }

    // --- Paiement manuel (capture d'écran) -------------------------------------------------------

    /** Preuve envoyée depuis l'app : capture stockée en base (le disque Render est éphémère). */
    public function submitProof(Delivery $delivery, PaymentMethod $method, string $reference, string $payerPhone, UploadedFile $screenshot): Payment
    {
        if (! in_array($method, PaymentMethod::mobileMoney(), true)) {
            throw ValidationException::withMessages(['method' => 'La carte bancaire se paie uniquement en ligne.']);
        }
        $reference = Payment::normalizeReference($reference);
        if ($reference === null) {
            throw ValidationException::withMessages(['transaction_ref' => 'Indiquez la référence de la transaction.']);
        }

        return DB::transaction(function () use ($delivery, $method, $reference, $payerPhone, $screenshot) {
            $fresh = $delivery->lockFresh();
            if (! $fresh->canSubmitPayment()) {
                throw ValidationException::withMessages(['payment' => 'Un paiement est déjà en cours de vérification ou confirmé.']);
            }
            Payment::lockReference($method, $reference);
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
            if ($reference !== null) {
                Payment::lockReference($method, $reference);
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
