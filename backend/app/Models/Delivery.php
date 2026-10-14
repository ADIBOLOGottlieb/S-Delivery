<?php

namespace App\Models;

use App\Enums\DeliveryStatus;
use App\Enums\DeliveryType;
use App\Enums\PaymentStatus;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

#[Fillable([
    'client_id', 'product_id', 'quantity', 'type',
    'pickup_address', 'pickup_lat', 'pickup_lng', 'pickup_contact_name', 'pickup_contact_phone',
    'dropoff_address', 'dropoff_lat', 'dropoff_lng', 'recipient_name', 'recipient_phone',
    'package_description', 'notes', 'scheduled_at', 'deadline_at', 'distance_km', 'delivery_fee',
    'items_amount', 'total_amount',
])]
class Delivery extends Model
{
    protected $attributes = [
        'status' => 'pending',
        'payment_status' => 'unpaid',
        'items_amount' => 0,
    ];

    protected static function booted(): void
    {
        static::creating(function (Delivery $delivery) {
            $delivery->reference ??= static::generateReference();
        });
    }

    public static function generateReference(): string
    {
        do {
            $reference = 'VD-'.strtoupper(Str::random(6));
        } while (static::where('reference', $reference)->exists());

        return $reference;
    }

    protected function casts(): array
    {
        return [
            'type' => DeliveryType::class,
            'status' => DeliveryStatus::class,
            'payment_status' => PaymentStatus::class,
            'pickup_lat' => 'float',
            'pickup_lng' => 'float',
            'dropoff_lat' => 'float',
            'dropoff_lng' => 'float',
            'distance_km' => 'float',
            'delivery_fee' => 'integer',
            'items_amount' => 'integer',
            'total_amount' => 'integer',
            'quantity' => 'integer',
            'scheduled_at' => 'datetime',
            'deadline_at' => 'datetime',
            'last_reminder_at' => 'datetime',
            'assigned_at' => 'datetime',
            'picked_up_at' => 'datetime',
            'delivered_at' => 'datetime',
            'cancelled_at' => 'datetime',
        ];
    }

    public function client(): BelongsTo
    {
        return $this->belongsTo(User::class, 'client_id');
    }

    public function courier(): BelongsTo
    {
        return $this->belongsTo(User::class, 'courier_id');
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class)->latest('id');
    }

    public function latestPayment(): HasOne
    {
        return $this->hasOne(Payment::class)->latestOfMany();
    }

    /** Photos des articles envoyées par le client (formulaire ou demande rapide). */
    public function photos(): BelongsToMany
    {
        return $this->belongsToMany(Media::class, 'delivery_photos')->withTimestamps()->orderBy('delivery_photos.id');
    }

    /** Demande rapide (chat) à l'origine de cette livraison. */
    public function deliveryRequest(): HasOne
    {
        return $this->hasOne(DeliveryRequest::class);
    }

    /** Le client peut encore ajouter des photos tant que le colis n'est pas récupéré. */
    public function acceptsPhotos(): bool
    {
        return in_array($this->status, [DeliveryStatus::Pending, DeliveryStatus::Assigned], true);
    }

    // --- Règles métier -------------------------------------------------------

    public function canSubmitPayment(): bool
    {
        return $this->status !== DeliveryStatus::Cancelled
            && in_array($this->payment_status, [PaymentStatus::Unpaid, PaymentStatus::Rejected], true);
    }

    /** Plus d'annulation depuis l'app dès qu'une preuve de paiement est envoyée (en vérification ou confirmée). */
    public function canBeCancelledByClient(): bool
    {
        return $this->status === DeliveryStatus::Pending
            && in_array($this->payment_status, [PaymentStatus::Unpaid, PaymentStatus::Rejected], true);
    }

    public function canBeAssigned(): bool
    {
        return in_array($this->status, [DeliveryStatus::Pending, DeliveryStatus::Assigned], true)
            && $this->payment_status === PaymentStatus::Verified;
    }

    /** Annulée alors que le client avait payé : l'agence doit le rembourser. */
    public function needsRefund(): bool
    {
        return $this->status === DeliveryStatus::Cancelled && $this->payment_status === PaymentStatus::Verified;
    }

    /** Relit la livraison en la verrouillant jusqu'à la fin de la transaction en cours. */
    public function lockFresh(): self
    {
        return static::whereKey($this->getKey())->lockForUpdate()->firstOrFail();
    }

    /**
     * Assigne (ou réassigne) un livreur.
     *
     * @return int|null livreur précédent, s'il a été remplacé
     */
    public function assignTo(User $courier): ?int
    {
        if (! $courier->isCourier() || ! $courier->is_active) {
            throw ValidationException::withMessages(['courier_id' => "Ce compte n'est pas un livreur actif."]);
        }

        return DB::transaction(function () use ($courier) {
            $fresh = $this->lockFresh();
            if (! $fresh->canBeAssigned()) {
                throw ValidationException::withMessages([
                    'courier_id' => 'Le paiement doit être confirmé et le colis pas encore récupéré pour assigner un livreur.',
                ]);
            }

            $previous = $fresh->courier_id !== null && $fresh->courier_id !== $courier->id ? $fresh->courier_id : null;
            $fresh->forceFill([
                'courier_id' => $courier->id,
                'status' => DeliveryStatus::Assigned,
                'assigned_at' => $fresh->courier_id === $courier->id ? $fresh->assigned_at : now(),
            ])->save();
            $this->syncFrom($fresh);

            return $previous;
        });
    }

    /** Transition effectuée par le livreur : assigned -> picked_up -> delivered. */
    public function advanceByCourier(DeliveryStatus $target, ?User $courier = null): void
    {
        DB::transaction(function () use ($target, $courier) {
            $fresh = $this->lockFresh();
            if ($courier && $fresh->courier_id !== $courier->id) {
                throw ValidationException::withMessages(['status' => 'Cette course a été confiée à un autre livreur.']);
            }

            $allowed = match ($fresh->status) {
                DeliveryStatus::Assigned => DeliveryStatus::PickedUp,
                DeliveryStatus::PickedUp => DeliveryStatus::Delivered,
                default => null,
            };

            if ($allowed !== $target) {
                throw ValidationException::withMessages([
                    'status' => "Transition impossible : {$fresh->status->label()} → {$target->label()}.",
                ]);
            }

            $fresh->status = $target;
            if ($target === DeliveryStatus::PickedUp) {
                $fresh->picked_up_at = now();
            } else {
                $fresh->delivered_at = now();
            }
            $fresh->save();
            $this->syncFrom($fresh);
        });
    }

    public function cancel(?string $reason = null): void
    {
        $this->cancelWhen(fn (self $fresh) => $fresh->status->isFinal() ? 'Cette livraison est déjà terminée.' : null, $reason);
    }

    /** Annulation depuis l'app : recontrôlée sous verrou (une preuve a pu arriver entre-temps). */
    public function cancelByClient(string $reason): void
    {
        $this->cancelWhen(fn (self $fresh) => $fresh->canBeCancelledByClient() ? null : $fresh->clientCancelRefusal(), $reason);
    }

    public function clientCancelRefusal(): string
    {
        return $this->payment_status === PaymentStatus::Submitted
            ? "Votre preuve de paiement est en cours de vérification : l'annulation n'est plus possible depuis l'application. Contactez l'agence."
            : "Cette livraison ne peut plus être annulée depuis l'application. Contactez l'agence.";
    }

    /** @param callable(self): ?string $refusal motif du refus, ou null si l'annulation est permise */
    private function cancelWhen(callable $refusal, ?string $reason): void
    {
        DB::transaction(function () use ($refusal, $reason) {
            $fresh = $this->lockFresh();
            if ($message = $refusal($fresh)) {
                throw ValidationException::withMessages(['status' => $message]);
            }

            $fresh->forceFill([
                'status' => DeliveryStatus::Cancelled,
                'cancelled_at' => now(),
                'cancel_reason' => $reason,
            ])->save();

            // La demande photo d'origine redevient « en discussion » : l'agence peut reprogrammer.
            DeliveryRequest::where('delivery_id', $fresh->id)
                ->where('status', DeliveryRequest::SCHEDULED)
                ->update(['status' => DeliveryRequest::OPEN]);

            $this->syncFrom($fresh);
        });
    }

    private function syncFrom(self $fresh): void
    {
        $this->setRawAttributes($fresh->getAttributes(), true);
    }
}
