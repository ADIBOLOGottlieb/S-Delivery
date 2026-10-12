<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

/**
 * Demande rapide d'un client habitué : photos des articles + discussion avec l'agence,
 * qui programme ensuite la livraison.
 */
class DeliveryRequest extends Model
{
    public const OPEN = 'open';

    public const SCHEDULED = 'scheduled';

    public const CLOSED = 'closed';

    protected $attributes = ['status' => self::OPEN];

    protected $fillable = ['district', 'recipient_phone', 'parcel_amount'];

    protected function casts(): array
    {
        return [
            'last_message_at' => 'datetime',
            'last_message_id' => 'integer',
            'admin_read_id' => 'integer',
            'client_read_id' => 'integer',
        ];
    }

    public function client(): BelongsTo
    {
        return $this->belongsTo(User::class, 'client_id');
    }

    public function delivery(): BelongsTo
    {
        return $this->belongsTo(Delivery::class);
    }

    public function messages(): HasMany
    {
        return $this->hasMany(ChatMessage::class)->oldest('id');
    }

    public function latestMessage(): HasOne
    {
        return $this->hasOne(ChatMessage::class)->latestOfMany();
    }

    public function reference(): string
    {
        return 'DR-'.str_pad((string) $this->id, 4, '0', STR_PAD_LEFT);
    }

    public function statusLabel(): string
    {
        return match ($this->status) {
            self::SCHEDULED => 'Livraison programmée',
            self::CLOSED => 'Clôturée',
            default => 'En discussion',
        };
    }

    /** Ajoute un message et met à jour l'ordre de la boîte de réception. */
    public function post(?User $sender, array $attributes): ChatMessage
    {
        $message = $this->messages()->create([...$attributes, 'sender_id' => $sender?->id]);

        // L'auteur a forcément lu la discussion jusqu'à son propre message.
        $read = match (true) {
            $sender === null => [],
            $sender->isAdmin() => ['admin_read_id' => $message->id],
            default => ['client_read_id' => $message->id],
        };
        $this->forceFill(['last_message_at' => now(), 'last_message_id' => $message->id, ...$read])->save();

        return $message;
    }

    public function markReadByClient(): void
    {
        $this->forceFill(['client_read_id' => $this->last_message_id])->save();
    }

    public function markReadByAdmin(): void
    {
        $this->forceFill(['admin_read_id' => $this->last_message_id])->save();
    }

    /** Messages de l'agence (ou système) non lus par le client. */
    public function unreadForClient(): int
    {
        return $this->messages()
            ->where(fn ($q) => $q->whereNull('sender_id')->orWhere('sender_id', '!=', $this->client_id))
            ->where('id', '>', $this->client_read_id ?? 0)
            ->count();
    }

    /** Nouveau message que l'agence n'a pas encore lu. */
    public function hasUnreadForAdmin(): bool
    {
        return $this->last_message_id !== null && $this->last_message_id > ($this->admin_read_id ?? 0);
    }
}
