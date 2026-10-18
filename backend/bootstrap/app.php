<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Exceptions\ThrottleRequestsException;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias([
            'role' => \App\Http\Middleware\EnsureRole::class,
        ]);
        $middleware->redirectGuestsTo(fn () => route('admin.login'));
        // Render termine le TLS sur son proxy : on lui fait confiance pour le schéma (URL https) et l'IP.
        // X-Forwarded-Host n'est pas pris en compte (hôte non falsifiable dans les URL générées) ;
        // les limites de connexion ne reposent pas sur l'IP seule (voir AppServiceProvider).
        $middleware->trustProxies(
            at: '*',
            headers: Request::HEADER_X_FORWARDED_FOR | Request::HEADER_X_FORWARDED_PORT | Request::HEADER_X_FORWARDED_PROTO,
        );
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );

        // Message en français pour toutes les limites de requêtes.
        $exceptions->render(function (ThrottleRequestsException $e, Request $request) {
            $seconds = (int) ($e->getHeaders()['Retry-After'] ?? 60);
            $minutes = max(1, (int) ceil($seconds / 60));
            $message = "Trop de tentatives. Réessayez dans {$minutes} minute".($minutes > 1 ? 's' : '').'.';

            if ($request->is('api/*') || $request->expectsJson()) {
                return response()->json(['message' => $message], 429, $e->getHeaders());
            }

            return back()->withInput($request->except('password'))->withErrors(['email' => $message]);
        });
    })->create();
