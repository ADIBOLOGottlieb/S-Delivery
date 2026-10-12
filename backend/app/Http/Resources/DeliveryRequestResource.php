<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\DeliveryRequest */
class DeliveryRequestResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'reference' => $this->reference(),
            'status' => $this->status,
            'status_label' => $this->statusLabel(),
            'unread' => $this->unreadForClient(),
            'district' => $this->district,
            'recipient_phone' => $this->recipient_phone,
            'parcel_amount' => $this->parcel_amount,
            'last_message' => $this->whenLoaded('latestMessage', fn () => $this->latestMessage
                ? new ChatMessageResource($this->latestMessage->setRelation('request', $this->resource))
                : null),
            'messages' => $this->whenLoaded('messages', fn () => ChatMessageResource::collection(
                $this->messages->each(fn ($m) => $m->setRelation('request', $this->resource))
            )),
            'delivery' => $this->whenLoaded('delivery', fn () => $this->delivery ? [
                'id' => $this->delivery->id,
                'reference' => $this->delivery->reference,
                'status_label' => $this->delivery->status->label(),
                'payment_status' => $this->delivery->payment_status->value,
                'total_amount' => $this->delivery->total_amount,
                'can_pay' => $this->delivery->canSubmitPayment(),
            ] : null),
            'last_message_at' => $this->last_message_at?->toIso8601String(),
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
