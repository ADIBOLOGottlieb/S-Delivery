<?php

namespace App\Support;

use App\Models\User;
use Closure;
use Illuminate\Database\Eloquent\Builder;

/** Identifiants de connexion : emails toujours en minuscules, numéros sous une seule écriture. */
class Identifier
{
    public static function email(?string $email): ?string
    {
        $email = mb_strtolower(trim((string) $email));

        return $email === '' ? null : $email;
    }

    /** Email ou numéro saisi à la connexion, sous sa forme canonique (clé des limites de tentatives). */
    public static function login(?string $login): string
    {
        $login = trim((string) $login);

        return str_contains($login, '@') ? mb_strtolower($login) : Phone::normalize($login);
    }

    /** Compte visé par un email (sans tenir compte de la casse) ou un numéro (toutes écritures). */
    public static function findUser(string $login): ?User
    {
        $login = trim($login);
        $email = self::email($login);

        return User::query()
            ->where(fn (Builder $q) => $q
                ->when($email !== null && str_contains($email, '@'), fn ($q) => $q->whereRaw('lower(email) = ?', [$email]))
                ->orWhereIn('phone_number', Phone::variants($login)))
            ->first();
    }

    /** Règle « email unique » insensible à la casse (les anciens comptes peuvent avoir des majuscules). */
    public static function uniqueEmail(?int $ignoreId = null): Closure
    {
        return function (string $attribute, mixed $value, Closure $fail) use ($ignoreId) {
            $email = self::email(is_string($value) ? $value : null);
            if ($email === null) {
                return;
            }
            $taken = User::whereRaw('lower(email) = ?', [$email])
                ->when($ignoreId, fn ($q) => $q->whereKeyNot($ignoreId))
                ->exists();
            if ($taken) {
                $fail('Cet email est déjà utilisé par un autre compte.');
            }
        };
    }
}
