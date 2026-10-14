<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\Delivery */
class DeliveryResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'reference' => $this->reference,
            'type' => $this->type->value,
            'type_label' => $this->type->label(),
            'status' => $this->status->value,
            'status_label' => $this->status->label(),
            'payment_status' => $this->payment_status->value,
            'payment_status_label' => $this->payment_status->label(),

            'pickup' => [
                'address' => $this->pickup_address,
                'lat' => $this->pickup_lat,
                'lng' => $this->pickup_lng,
                // Commande de produit : le contact du point A est le vendeur, jamais le client (null si inconnu).
                'contact_name' => $this->pickup_contact_name ?? ($this->product_id ? null : $this->client?->name),
                'contact_phone' => $this->pickup_contact_phone ?? ($this->product_id ? null : $this->client?->phone_number),
            ],
            'dropoff' => [
                'address' => $this->dropoff_address,
                'lat' => $this->dropoff_lat,
                'lng' => $this->dropoff_lng,
                'contact_name' => $this->recipient_name,
                'contact_phone' => $this->recipient_phone,
            ],

            'package_description' => $this->package_description,
            'notes' => $this->notes,
            'product' => $this->whenLoaded('product', fn () => $this->product ? [
                'id' => $this->product->id,
                'name' => $this->product->name,
            ] : null),
            'quantity' => $this->quantity,
            'photos' => $this->whenLoaded('photos', fn () => $this->photos->map(fn ($m) => $m->url())->values()),
            'request_id' => $this->whenLoaded('deliveryRequest', fn () => $this->deliveryRequest?->id),
            // Demande photo : montant à encaisser auprès du destinataire.
            'parcel_amount' => $this->deliveryRequest?->parcel_amount,
            'scheduled_at' => $this->scheduled_at?->toIso8601String(),
            'deadline_at' => $this->deadline_at?->toIso8601String(),
            'is_urgent' => \App\Services\DeliveryReminder::isUrgent($this->resource),

            'distance_km' => $this->distance_km,
            'delivery_fee' => $this->delivery_fee,
            'items_amount' => $this->items_amount,
            'total_amount' => $this->total_amount,

            'client' => $this->whenLoaded('client', fn () => [
                'name' => $this->client->name,
                'phone_number' => $this->client->phone_number,
            ]),
            'courier' => $this->whenLoaded('courier', fn () => $this->courier ? [
                'name' => $this->courier->name,
                'phone_number' => $this->courier->phone_number,
                'vehicle' => $this->courier->vehicle,
            ] : null),
            'latest_payment' => $this->whenLoaded('latestPayment', fn () => $this->latestPayment
                ? new PaymentResource($this->latestPayment)
                : null),

            'can_pay' => $this->canSubmitPayment(),
            'can_cancel' => $this->canBeCancelledByClient(),

            'created_at' => $this->created_at?->toIso8601String(),
            'assigned_at' => $this->assigned_at?->toIso8601String(),
            'picked_up_at' => $this->picked_up_at?->toIso8601String(),
            'delivered_at' => $this->delivered_at?->toIso8601String(),
            'cancelled_at' => $this->cancelled_at?->toIso8601String(),
            'cancel_reason' => $this->cancel_reason,
        ];
    }
}
