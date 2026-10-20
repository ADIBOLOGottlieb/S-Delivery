<?php

use App\Http\Controllers\Api\AppInfoController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\CheckoutController;
use App\Http\Controllers\Api\CourierDeliveryController;
use App\Http\Controllers\Api\CronController;
use App\Http\Controllers\Api\DeliveryChatController;
use App\Http\Controllers\Api\DeliveryController;
use App\Http\Controllers\Api\PasswordResetController;
use App\Http\Controllers\Api\PaymentWebhookController;
use App\Http\Controllers\Api\ProfileController;
use App\Http\Controllers\Api\RequestController;
use Illuminate\Support\Facades\Route;

// Identifiants de route numériques : « /deliveries/abc » répond 404 au lieu d'une erreur SQL.
Route::patterns(['delivery' => '[0-9]+', 'deliveryRequest' => '[0-9]+', 'payment' => '[0-9]+']);

Route::prefix('v1')->group(function () {
    Route::middleware('throttle:auth')->group(function () {
        Route::post('/register', [AuthController::class, 'register']);
        Route::post('/login', [AuthController::class, 'login']);
    });

    // Mot de passe oublié : code envoyé par email, sans passer par l'agence.
    Route::post('/password/forgot', [PasswordResetController::class, 'forgot'])->middleware('throttle:password-forgot');
    Route::post('/password/reset', [PasswordResetController::class, 'reset'])->middleware('throttle:password-reset');

    // Tâches périodiques (rappels livreurs), protégées par X-Cron-Key.
    Route::post('/cron/run', CronController::class)->middleware('throttle:30,1');

    // Notifications des agrégateurs (sans authentification : chaque paiement est revérifié via leur API).
    Route::middleware('throttle:120,1')->prefix('webhooks')->group(function () {
        Route::post('/kkiapay', [PaymentWebhookController::class, 'kkiapay'])->name('webhooks.kkiapay');
        Route::post('/paygate', [PaymentWebhookController::class, 'paygate'])->name('webhooks.paygate');
    });

    Route::middleware('auth:sanctum')->group(function () {
        Route::get('/me', [AuthController::class, 'me']);
        Route::post('/logout', [AuthController::class, 'logout']);
        // Suppression du compte (exigence Google Play) : anonymisation, historique comptable conservé.
        Route::delete('/me', [ProfileController::class, 'deleteAccount'])->middleware('throttle:5,1');

        Route::post('/me/device-token', [AuthController::class, 'deviceToken']);
        Route::post('/me/avatar', [ProfileController::class, 'updateAvatar'])->middleware('throttle:20,1');
        Route::delete('/me/avatar', [ProfileController::class, 'deleteAvatar']);
        Route::put('/me/credentials', [ProfileController::class, 'updateCredentials'])->middleware('throttle:10,1');

        // Moyens de paiement, numéro de l'agence et liens publics.
        Route::get('/payment-info', [AppInfoController::class, 'paymentInfo']);

        Route::middleware('role:client')->group(function () {
            Route::get('/deliveries', [DeliveryController::class, 'index']);
            Route::post('/deliveries', [DeliveryController::class, 'store']);
            Route::post('/deliveries/quote', [DeliveryController::class, 'quote']);
            Route::get('/deliveries/{delivery}', [DeliveryController::class, 'show']);
            Route::post('/deliveries/{delivery}/cancel', [DeliveryController::class, 'cancel']);
            Route::post('/deliveries/{delivery}/payment', [DeliveryController::class, 'submitPayment']);
            Route::post('/deliveries/{delivery}/photos', [DeliveryController::class, 'addPhoto'])->middleware('throttle:30,1');
            Route::post('/deliveries/{delivery}/rating', [DeliveryController::class, 'rate'])->middleware('throttle:10,1');

            // Paiement intégré (Flooz, Mixx by Yas, carte) via l'agrégateur.
            Route::post('/deliveries/{delivery}/checkout', [CheckoutController::class, 'store'])->middleware('throttle:10,1');
            Route::get('/deliveries/{delivery}/payments/{payment}', [CheckoutController::class, 'show']);

            // Discussion de la course avec le livreur et l'agence.
            Route::get('/deliveries/{delivery}/messages', [DeliveryChatController::class, 'clientIndex']);
            Route::post('/deliveries/{delivery}/messages', [DeliveryChatController::class, 'clientStore'])->middleware('throttle:60,1');

            // Demandes rapides (tout client) : photos + chat avec l'agence.
            Route::get('/requests', [RequestController::class, 'index']);
            Route::post('/requests', [RequestController::class, 'store'])->middleware('throttle:10,1');
            Route::get('/requests/{deliveryRequest}', [RequestController::class, 'show']);
            Route::post('/requests/{deliveryRequest}/messages', [RequestController::class, 'message'])->middleware('throttle:60,1');
        });

        Route::middleware('role:livreur')->prefix('courier')->group(function () {
            Route::get('/deliveries', [CourierDeliveryController::class, 'index']);
            Route::get('/deliveries/{delivery}', [CourierDeliveryController::class, 'show']);
            // Code de remise saisi à la livraison : limité pour empêcher de le deviner.
            Route::post('/deliveries/{delivery}/status', [CourierDeliveryController::class, 'updateStatus'])->middleware('throttle:12,1');
            // Position partagée pendant les courses (suivi en direct côté client).
            Route::post('/location', [CourierDeliveryController::class, 'location'])->middleware('throttle:30,1');

            Route::get('/deliveries/{delivery}/messages', [DeliveryChatController::class, 'courierIndex']);
            Route::post('/deliveries/{delivery}/messages', [DeliveryChatController::class, 'courierStore'])->middleware('throttle:60,1');
        });
    });
});
