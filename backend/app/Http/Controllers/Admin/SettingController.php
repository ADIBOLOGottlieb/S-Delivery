<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Setting;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

class SettingController extends Controller
{
    public function edit(): View
    {
        $settings = collect(Setting::DEFAULTS)->mapWithKeys(fn ($default, $key) => [$key => Setting::get($key)]);

        return view('admin.settings', compact('settings'));
    }

    public function update(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'merchant_name' => ['required', 'string', 'max:255'],
            'flooz_merchant_number' => ['nullable', 'string', 'max:30'],
            'mixx_merchant_number' => ['nullable', 'string', 'max:30'],
            'payment_instructions' => ['nullable', 'string', 'max:1000'],
            'base_fee' => ['required', 'integer', 'min:0'],
            'per_km_fee' => ['required', 'integer', 'min:0'],
            'express_fee' => ['required', 'integer', 'min:0'],
            'min_fee' => ['required', 'integer', 'min:0'],
        ]);

        Setting::put(array_map(fn ($v) => $v === null ? null : (string) $v, $data));

        return back()->with('success', 'Réglages enregistrés.');
    }
}
