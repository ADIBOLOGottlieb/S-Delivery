<?php

namespace App\Enums;

enum PaymentMethod: string
{
    case Flooz = 'flooz';
    case Mixx = 'mixx';
    // Visa / Mastercard : uniquement via l'agrégateur KKiaPay (pas de numéro marchand).
    case Card = 'card';

    public function label(): string
    {
        return match ($this) {
            self::Flooz => 'Flooz (Moov Africa)',
            self::Mixx => 'Mixx by Yas',
            self::Card => 'Carte bancaire',
        };
    }

    /** Moyens payables par virement au numéro marchand (mode manuel). */
    public static function mobileMoney(): array
    {
        return [self::Flooz, self::Mixx];
    }
}
