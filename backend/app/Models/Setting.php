<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Cache;

/**
 * Réglages clé/valeur modifiables depuis le panneau admin
 * (numéros marchands Flooz / Mixx by Yas, tarification...).
 */
#[Fillable(['key', 'value'])]
class Setting extends Model
{
    protected $primaryKey = 'key';

    public $incrementing = false;

    protected $keyType = 'string';

    public const DEFAULTS = [
        'merchant_name' => 'S-Delivery',
        'flooz_merchant_number' => '',
        'mixx_merchant_number' => '',
        // Numéro appelé par « Contacter l'agence » dans l'app.
        'support_phone' => '',
        // Contact affiché dans la politique de confidentialité et la page de suppression de compte.
        'support_email' => '',
        'payment_instructions' => "Envoyez le montant exact au numéro marchand, puis joignez la capture d'écran de la transaction.",
        'base_fee' => '500',
        'per_km_fee' => '150',
        'express_fee' => '1000',
        'min_fee' => '1000',
        // auto : agrégateur si ses clés sont configurées, sinon manuel ; manual : capture d'écran ;
        // simulation : paiement fictif pour les tests (aucun argent débité).
        'payment_mode' => 'auto',
    ];

    public static function get(string $key): ?string
    {
        $all = Cache::rememberForever('settings', fn () => static::query()->pluck('value', 'key')->all());

        return $all[$key] ?? self::DEFAULTS[$key] ?? null;
    }

    public static function int(string $key): int
    {
        return (int) static::get($key);
    }

    /** @param array<string, ?string> $values */
    public static function put(array $values): void
    {
        foreach ($values as $key => $value) {
            static::query()->updateOrCreate(['key' => $key], ['value' => $value]);
        }
        Cache::forget('settings');
    }
}
