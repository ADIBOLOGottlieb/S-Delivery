<?php

namespace App\Providers;

use App\Support\Identifier;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Database\Query\Builder as QueryBuilder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\URL;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Derrière le proxy TLS de Render : les URL générées restent en https.
        if ($this->app->isProduction()) {
            URL::forceScheme('https');
        }

        $this->registerSearchMacros();
        $this->registerRateLimiters();
    }

    /**
     * whereContains('name', $terme) : recherche « contient », insensible à la casse
     * (ilike sous PostgreSQL, lower() like ailleurs) ; % et _ saisis sont cherchés tels quels.
     */
    private function registerSearchMacros(): void
    {
        QueryBuilder::macro('whereContains', function (string $column, string $term, string $boolean = 'and') {
            /** @var QueryBuilder $this */
            $like = '%'.addcslashes($term, '%_\\').'%';
            $wrapped = $this->getGrammar()->wrap($column);
            $sql = $this->getConnection()->getDriverName() === 'pgsql'
                ? "{$wrapped} ilike ? escape '\\'"
                : "lower({$wrapped}) like lower(?) escape '\\'";

            return $this->whereRaw($sql, [$like], $boolean);
        });

        QueryBuilder::macro('orWhereContains', function (string $column, string $term) {
            /** @var QueryBuilder $this */
            return $this->whereContains($column, $term, 'or');
        });
    }

    /**
     * Limites des routes d'authentification. L'IP seule ne suffit pas (en-têtes de proxy falsifiables,
     * IP partagées) : chaque route est aussi limitée par identifiant visé et globalement.
     */
    private function registerRateLimiters(): void
    {
        $byIdentifier = function (Request $request, Limit $limit, string $prefix): ?Limit {
            $raw = $request->input('login') ?? $request->input('phone_number') ?? $request->input('email');
            $identifier = is_string($raw) ? Identifier::login($raw) : '';

            return $identifier === '' ? null : $limit->by($prefix.':id:'.sha1($identifier));
        };

        // Inscription / connexion de l'app.
        RateLimiter::for('auth', fn (Request $request) => array_values(array_filter([
            Limit::perMinute(300)->by('auth:global'),
            Limit::perMinute(10)->by('auth:ip:'.$request->ip()),
            $byIdentifier($request, Limit::perMinute(10), 'auth'),
        ])));

        // Mot de passe oublié : chaque demande envoie un email (quota SMTP gratuit limité).
        RateLimiter::for('password-forgot', fn (Request $request) => array_values(array_filter([
            Limit::perHour(60)->by('forgot:global'),
            Limit::perMinutes(10, 5)->by('forgot:ip:'.$request->ip()),
            $byIdentifier($request, Limit::perMinutes(10, 3), 'forgot'),
        ])));

        RateLimiter::for('password-reset', fn (Request $request) => array_values(array_filter([
            Limit::perMinutes(10, 300)->by('reset:global'),
            Limit::perMinutes(10, 10)->by('reset:ip:'.$request->ip()),
            $byIdentifier($request, Limit::perMinutes(10, 10), 'reset'),
        ])));

        // Panneau admin.
        RateLimiter::for('admin-login', fn (Request $request) => array_values(array_filter([
            Limit::perMinute(60)->by('admin:global'),
            Limit::perMinute(10)->by('admin:ip:'.$request->ip()),
            $byIdentifier($request, Limit::perMinutes(15, 10), 'admin'),
        ])));
    }
}
