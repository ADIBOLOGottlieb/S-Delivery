<?php

namespace App\Support;

/** Numéros de téléphone togolais : une seule écriture (+228XXXXXXXX) pour éviter les doublons. */
class Phone
{
    /** « 90 11 22 33 », « 22890112233 », « 00228 90-11-22-33 » → « +22890112233 ». */
    public static function normalize(string $raw): string
    {
        $digits = preg_replace('/\D/', '', $raw) ?? '';
        if (str_starts_with($digits, '00')) {
            $digits = substr($digits, 2);
        }
        if (strlen($digits) === 8) {
            $digits = '228'.$digits;
        }

        return $digits === '' ? trim($raw) : '+'.$digits;
    }

    /** Numéro exploitable : indicatif + 8 chiffres au minimum. */
    public static function isValid(string $raw): bool
    {
        return strlen(ltrim(self::normalize($raw), '+')) >= 11;
    }

    /**
     * Écritures possibles d'un même numéro, pour retrouver aussi les comptes
     * enregistrés avant la normalisation (ex. « 90112233 » saisi tel quel).
     *
     * @return list<string>
     */
    public static function variants(string $raw): array
    {
        $normalized = self::normalize($raw);
        $digits = ltrim($normalized, '+');

        return array_values(array_unique(array_filter([
            trim($raw),
            $normalized,
            $digits,
            strlen($digits) > 8 ? substr($digits, -8) : null,
        ])));
    }

    /** Lien WhatsApp vers ce numéro avec un message pré-rempli. */
    public static function whatsappLink(string $phone, string $message): string
    {
        return 'https://wa.me/'.ltrim(self::normalize($phone), '+').'?text='.rawurlencode($message);
    }
}
