<?php

namespace App\Models;

use App\Enums\PaymentMethod;
use App\Enums\PaymentStatus;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'delivery_id', 'method', 'transaction_ref', 'payer_phone', 'amount',
    'screenshot_path', 'screenshot_media_id', 'status', 'reviewed_by', 'reviewed_at', 'rejection_reason',
])]
class Payment extends Model
{
    protected function casts(): array
    {
        return [
            'method' => PaymentMethod::class,
            'status' => PaymentStatus::class,
            'amount' => 'integer',
            'reviewed_at' => 'datetime',
        ];
    }

    public function delivery(): BelongsTo
    {
        return $this->belongsTo(Delivery::class);
    }

    public function reviewer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }

    /** Capture d'écran de la transaction, stockée en base. */
    public function screenshot(): BelongsTo
    {
        return $this->belongsTo(Media::class, 'screenshot_media_id');
    }

    /** Capture en base, ou ancien fichier sur disque (avant la migration). */
    public function hasScreenshot(): bool
    {
        return $this->screenshot_media_id !== null || $this->screenshot_path !== null;
    }

    /** « mx 12 ab » → « MX12AB » : une référence ne peut pas resservir sous une autre écriture. */
    public static function normalizeReference(?string $reference): ?string
    {
        $normalized = mb_strtoupper(preg_replace('/\s+/u', '', (string) $reference) ?? '');

        return $normalized === '' ? null : $normalized;
    }

    /**
     * Verrou sur une référence, à prendre dans la transaction avant referenceInUse() : deux preuves
     * simultanées (sur deux livraisons différentes) ne peuvent pas réutiliser la même référence.
     * PostgreSQL : verrou consultatif libéré au commit. SQLite (tests) sérialise déjà les écritures.
     */
    public static function lockReference(PaymentMethod|string $method, string $normalized): void
    {
        $connection = (new static)->getConnection();
        if ($connection->getDriverName() !== 'pgsql') {
            return;
        }

        $method = $method instanceof PaymentMethod ? $method->value : $method;
        $connection->select('select pg_advisory_xact_lock(hashtext(?))', ["payment-ref:{$method}:{$normalized}"]);
    }

    /** Référence déjà utilisée par un paiement non refusé (anciennes écritures comprises). */
    public static function referenceInUse(PaymentMethod|string $method, string $normalized): bool
    {
        return static::query()
            ->where('method', $method instanceof PaymentMethod ? $method->value : $method)
            ->whereRaw("upper(replace(transaction_ref, ' ', '')) = ?", [$normalized])
            ->where('status', '!=', PaymentStatus::Rejected)
            ->exists();
    }
}
