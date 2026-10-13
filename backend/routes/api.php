<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\CatalogController;
use App\Http\Controllers\Api\CourierDeliveryController;
use App\Http\Controllers\Api\CronController;
use App\Http\Controllers\Api\DeliveryController;
use App\Http\Controllers\Api\ProfileController;
use App\Http\Controllers\Api\RequestController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {
    Route::middleware('throttle:10,1')->group(function () {
        Route::post('/register', [AuthController::class, 'register']);
        Route::post('/login', [AuthController::class, 'login']);
    });

    // Tâches périodiques (rappels livreurs), protégées par X-Cron-Key.
    Route::post('/cron/run', CronController::class)->middleware('throttle:30,1');

    Route::middleware('auth:sanctum')->group(function () {
        Route::get('/me', [AuthController::class, 'me']);
        Route::post('/logout', [AuthController::class, 'logout']);

        Route::post('/me/device-token', [AuthController::class, 'deviceToken']);
        Route::post('/me/avatar', [ProfileController::class, 'updateAvatar'])->middleware('throttle:20,1');
        Route::delete('/me/avatar', [ProfileController::class, 'deleteAvatar']);
        Route::put('/me/credentials', [ProfileController::class, 'updateCredentials'])->middleware('throttle:10,1');

        Route::get('/products', [CatalogController::class, 'products']);
        Route::get('/subcategories', [CatalogController::class, 'subcategories']);
        Route::get('/promotions', [CatalogController::class, 'promotions']);
        Route::get('/payment-info', [CatalogController::class, 'paymentInfo']);

        Route::middleware('role:client')->group(function () {
            Route::get('/deliveries', [DeliveryController::class, 'index']);
            Route::post('/deliveries', [DeliveryController::class, 'store']);
            Route::post('/deliveries/quote', [DeliveryController::class, 'quote']);
            Route::get('/deliveries/{delivery}', [DeliveryController::class, 'show']);
            Route::post('/deliveries/{delivery}/cancel', [DeliveryController::class, 'cancel']);
            Route::post('/deliveries/{delivery}/payment', [DeliveryController::class, 'submitPayment']);
            Route::post('/deliveries/{delivery}/photos', [DeliveryController::class, 'addPhoto'])->middleware('throttle:30,1');

            // Demandes rapides (clients habitués) : photos + chat avec l'agence.
            Route::get('/requests', [RequestController::class, 'index']);
            Route::post('/requests', [RequestController::class, 'store'])->middleware('throttle:10,1');
            Route::get('/requests/{deliveryRequest}', [RequestController::class, 'show']);
            Route::post('/requests/{deliveryRequest}/messages', [RequestController::class, 'message'])->middleware('throttle:60,1');
        });

        Route::middleware('role:livreur')->prefix('courier')->group(function () {
            Route::get('/deliveries', [CourierDeliveryController::class, 'index']);
            Route::get('/deliveries/{delivery}', [CourierDeliveryController::class, 'show']);
            Route::post('/deliveries/{delivery}/status', [CourierDeliveryController::class, 'updateStatus']);
        });
    });
});
