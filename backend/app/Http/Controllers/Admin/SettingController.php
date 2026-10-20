<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Setting;
use App\Services\Payments\PaymentService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

class SettingController extends Controller
{
    public function edit(PaymentService $payments): View
    {
        $settings = collect(Setting::DEFAULTS)->mapWithKeys(fn ($default, $key) => [$key => Setting::get($key)]);

        // Les clés d'agrégateur sont des secrets : affichées en lecture seule, modifiables uniquement dans .env.
        $gateway = [
            'mode' => $payments->mode(),
            'requested' => config('payments.gateway'),
            'configured' => $payments->configuredGateway()?->name(),
            'active' => $payments->gateway()?->name(),
            'sandbox' => (bool) config('payments.kkiapay.sandbox'),
            'webhook_kkiapay' => route('webhooks.kkiapay'),
            'webhook_paygate' => route('webhooks.paygate'),
        ];

        return view('admin.settings', compact('settings', 'gateway'));
    }

    public function update(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'merchant_name' => ['required', 'string', 'max:255'],
            'flooz_merchant_number' => ['nullable', 'string', 'max:30'],
            'mixx_merchant_number' => ['nullable', 'string', 'max:30'],
            'support_phone' => ['nullable', 'string', 'max:30'],
            'support_email' => ['nullable', 'email', 'max:255'],
            'payment_instructions' => ['nullable', 'string', 'max:1000'],
            'payment_mode' => ['required', 'in:auto,manual,simulation'],
            'base_fee' => ['required', 'integer', 'min:0'],
            'per_km_fee' => ['required', 'integer', 'min:0'],
            'express_fee' => ['required', 'integer', 'min:0'],
            'min_fee' => ['required', 'integer', 'min:0'],
        ]);

        Setting::put(array_map(fn ($v) => $v === null ? null : (string) $v, $data));

        return back()->with('success', 'Réglages enregistrés.');
    }
}
