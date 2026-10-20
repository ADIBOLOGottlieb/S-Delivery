<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\DeliveryMessage */
class DeliveryMessageResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            // client | courier | agency | system
            'from' => $this->senderRole(),
            'is_mine' => $this->sender_id !== null && $this->sender_id === $request->user()?->id,
            'sender_name' => $this->sender?->name,
            'body' => $this->body,
            'photo_url' => $this->media?->url(),
            'lat' => $this->lat,
            'lng' => $this->lng,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
