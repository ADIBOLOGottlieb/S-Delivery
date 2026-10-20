<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Message de la discussion d'une course : texte, photo ou position. */
#[Fillable(['sender_id', 'body', 'media_id', 'lat', 'lng'])]
class DeliveryMessage extends Model
{
    protected function casts(): array
    {
        return ['lat' => 'float', 'lng' => 'float'];
    }

    public function delivery(): BelongsTo
    {
        return $this->belongsTo(Delivery::class);
    }

    public function sender(): BelongsTo
    {
        return $this->belongsTo(User::class, 'sender_id');
    }

    public function media(): BelongsTo
    {
        return $this->belongsTo(Media::class);
    }

    /** client | courier | agency | system, vu depuis la livraison. */
    public function senderRole(): string
    {
        return match (true) {
            $this->sender_id === null => 'system',
            $this->sender_id === $this->delivery?->client_id => 'client',
            $this->sender_id === $this->delivery?->courier_id => 'courier',
            $this->sender?->isCourier() === true => 'courier',
            default => 'agency',
        };
    }
}
