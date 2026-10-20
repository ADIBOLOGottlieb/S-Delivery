<?php

namespace App\Models;

use App\Enums\Role;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

#[Fillable(['name', 'email', 'phone_number', 'district', 'password', 'role', 'is_active', 'vehicle'])]
#[Hidden(['password', 'remember_token', 'fcm_token'])]
class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, Notifiable;

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'role' => Role::class,
            'is_active' => 'boolean',
            'anonymized_at' => 'datetime',
            'last_lat' => 'float',
            'last_lng' => 'float',
            'located_at' => 'datetime',
        ];
    }

    /** Position récente du livreur (partagée pendant ses courses), sinon null. */
    public function freshLocation(int $maxAgeMinutes = 10): ?array
    {
        if ($this->last_lat === null || $this->last_lng === null || ! $this->located_at?->gt(now()->subMinutes($maxAgeMinutes))) {
            return null;
        }

        return ['lat' => $this->last_lat, 'lng' => $this->last_lng, 'updated_at' => $this->located_at->toIso8601String()];
    }

    /** Compte supprimé par son titulaire : ne peut plus être réactivé. */
    public function isAnonymized(): bool
    {
        return $this->anonymized_at !== null;
    }

    public function avatar(): BelongsTo
    {
        return $this->belongsTo(Media::class, 'avatar_media_id');
    }

    public function avatarUrl(): ?string
    {
        return $this->avatar_media_id ? route('media.show', $this->avatar()->value('uuid')) : null;
    }

    public function deliveryRequests(): HasMany
    {
        return $this->hasMany(DeliveryRequest::class, 'client_id');
    }

    public function isAdmin(): bool
    {
        return $this->role === Role::Admin;
    }

    public function isCourier(): bool
    {
        return $this->role === Role::Courier;
    }

    public function isClient(): bool
    {
        return $this->role === Role::Client;
    }

    /** Livraisons demandées par ce client. */
    public function deliveries(): HasMany
    {
        return $this->hasMany(Delivery::class, 'client_id');
    }

    /** Livraisons assignées à ce livreur. */
    public function assignedDeliveries(): HasMany
    {
        return $this->hasMany(Delivery::class, 'courier_id');
    }

    public function scopeCouriers(Builder $query): Builder
    {
        return $query->where('role', Role::Courier);
    }
}
