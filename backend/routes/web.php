<?php

use App\Http\Controllers\Admin\AuthController;
use App\Http\Controllers\Admin\ClientAccountController;
use App\Http\Controllers\Admin\DeliveryController;
use App\Http\Controllers\Admin\ProductController;
use App\Http\Controllers\Admin\PromotionController;
use App\Http\Controllers\Admin\RequestController;
use App\Http\Controllers\Admin\SubcategoryController;
use App\Http\Controllers\Admin\SettingController;
use App\Http\Controllers\Admin\UserController;
use App\Http\Controllers\MediaController;
use Illuminate\Support\Facades\Route;

Route::redirect('/', '/admin');

// Images envoyées depuis l'app (profil, articles, chat), stockées en base.
Route::get('/media/{uuid}', [MediaController::class, 'show'])->whereUuid('uuid')->name('media.show');


Route::prefix('admin')->name('admin.')->group(function () {
    Route::middleware('guest')->group(function () {
        Route::get('/login', [AuthController::class, 'showLogin'])->name('login');
        Route::post('/login', [AuthController::class, 'login'])->middleware('throttle:10,1');
    });

    Route::middleware(['auth', 'role:admin'])->group(function () {
        Route::post('/logout', [AuthController::class, 'logout'])->name('logout');

        Route::get('/', [DeliveryController::class, 'dashboard'])->name('dashboard');

        Route::get('/deliveries', [DeliveryController::class, 'index'])->name('deliveries.index');
        Route::get('/deliveries/{delivery}', [DeliveryController::class, 'show'])->name('deliveries.show');
        Route::post('/deliveries/{delivery}/assign', [DeliveryController::class, 'assign'])->name('deliveries.assign');
        Route::post('/deliveries/{delivery}/cancel', [DeliveryController::class, 'cancel'])->name('deliveries.cancel');

        Route::post('/deliveries/{delivery}/confirm-payment', [DeliveryController::class, 'confirmPayment'])->name('deliveries.confirm-payment');
        Route::post('/payments/{payment}/approve', [DeliveryController::class, 'approvePayment'])->name('payments.approve');
        Route::post('/payments/{payment}/reject', [DeliveryController::class, 'rejectPayment'])->name('payments.reject');
        Route::get('/payments/{payment}/screenshot', [DeliveryController::class, 'screenshot'])->name('payments.screenshot');

        // Demandes rapides (photos + chat) des clients habitués.
        Route::get('/requests', [RequestController::class, 'index'])->name('requests.index');
        Route::get('/requests/{deliveryRequest}', [RequestController::class, 'show'])->name('requests.show');
        Route::post('/requests/{deliveryRequest}/reply', [RequestController::class, 'reply'])->name('requests.reply');
        Route::post('/requests/{deliveryRequest}/schedule', [RequestController::class, 'schedule'])->name('requests.schedule');
        Route::post('/requests/{deliveryRequest}/close', [RequestController::class, 'close'])->name('requests.close');

        Route::get('/couriers', [UserController::class, 'couriers'])->name('couriers.index');
        Route::get('/couriers/create', [UserController::class, 'create'])->name('couriers.create');
        Route::post('/couriers', [UserController::class, 'store'])->name('couriers.store');
        Route::get('/couriers/{courier}/edit', [UserController::class, 'edit'])->name('couriers.edit');
        Route::put('/couriers/{courier}', [UserController::class, 'update'])->name('couriers.update');

        Route::get('/clients', [UserController::class, 'clients'])->name('clients.index');
        // Anciens clients de l'agence : création / import avec identifiants à leur transmettre.
        Route::get('/clients/create', [ClientAccountController::class, 'create'])->name('clients.create');
        Route::post('/clients', [ClientAccountController::class, 'store'])->name('clients.store');
        Route::get('/clients/import', [ClientAccountController::class, 'importForm'])->name('clients.import');
        Route::post('/clients/import', [ClientAccountController::class, 'import'])->name('clients.import.store');
        Route::get('/clients/credentials', [ClientAccountController::class, 'credentials'])->name('clients.credentials');
        Route::post('/clients/{client}/password', [ClientAccountController::class, 'resetPassword'])->name('clients.password');
        Route::post('/clients/{client}/toggle', [UserController::class, 'toggleClient'])->name('clients.toggle');
        Route::post('/clients/{client}/regular', [UserController::class, 'toggleRegular'])->name('clients.regular');

        Route::resource('products', ProductController::class)->except('show');

        Route::get('/subcategories', [SubcategoryController::class, 'index'])->name('subcategories.index');
        Route::post('/subcategories', [SubcategoryController::class, 'store'])->name('subcategories.store');
        Route::put('/subcategories', [SubcategoryController::class, 'update'])->name('subcategories.update');
        Route::delete('/subcategories/{subcategory}', [SubcategoryController::class, 'destroy'])->name('subcategories.destroy');

        Route::resource('promotions', PromotionController::class)->except('show');
        Route::post('/promotions/{promotion}/push', [PromotionController::class, 'push'])->name('promotions.push');

        Route::get('/settings', [SettingController::class, 'edit'])->name('settings.edit');
        Route::put('/settings', [SettingController::class, 'update'])->name('settings.update');
    });
});
