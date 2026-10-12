@extends('layouts.admin')

@section('title', 'Réglages')

@section('content')
    <h1 class="text-2xl font-bold mb-4">Réglages</h1>

    <form method="POST" action="{{ route('admin.settings.update') }}" class="space-y-6 max-w-2xl">
        @csrf @method('PUT')

        <section class="bg-white rounded-lg shadow-sm p-6 space-y-4">
            <h2 class="font-semibold">Paiement Flooz / Mixx by Yas</h2>
            <p class="text-sm text-gray-500">
                Le client vire le montant sur un de ces numéros puis envoie la capture d'écran dans l'app.
                Vous vérifiez la transaction sur le compte marchand et confirmez depuis la fiche de la livraison
                (ou validez directement un paiement en espèces). Renseignez au moins un numéro.
            </p>
            <div>
                <label class="block text-sm font-medium mb-1">Nom du compte marchand</label>
                <input name="merchant_name" value="{{ old('merchant_name', $settings['merchant_name']) }}" required class="w-full border rounded px-3 py-2">
            </div>
            <div class="grid grid-cols-2 gap-4">
                <div>
                    <label class="block text-sm font-medium mb-1">Numéro marchand Flooz (Moov Africa)</label>
                    <input name="flooz_merchant_number" value="{{ old('flooz_merchant_number', $settings['flooz_merchant_number']) }}" class="w-full border rounded px-3 py-2">
                </div>
                <div>
                    <label class="block text-sm font-medium mb-1">Numéro marchand Mixx by Yas</label>
                    <input name="mixx_merchant_number" value="{{ old('mixx_merchant_number', $settings['mixx_merchant_number']) }}" class="w-full border rounded px-3 py-2">
                </div>
            </div>
            <div>
                <label class="block text-sm font-medium mb-1">Instructions affichées au client</label>
                <textarea name="payment_instructions" rows="3" class="w-full border rounded px-3 py-2">{{ old('payment_instructions', $settings['payment_instructions']) }}</textarea>
            </div>
        </section>

        <section class="bg-white rounded-lg shadow-sm p-6 space-y-4">
            <h2 class="font-semibold">Tarification (FCFA)</h2>
            <p class="text-sm text-gray-500">Frais = forfait + distance estimée × prix au km (+ supplément Express), avec un minimum, arrondi à 50 F.</p>
            <div class="grid grid-cols-2 gap-4">
                @foreach (['base_fee' => 'Forfait de base', 'per_km_fee' => 'Prix par km', 'express_fee' => 'Supplément Express', 'min_fee' => 'Frais minimum'] as $key => $label)
                    <div>
                        <label class="block text-sm font-medium mb-1">{{ $label }}</label>
                        <input name="{{ $key }}" type="number" min="0" value="{{ old($key, $settings[$key]) }}" required class="w-full border rounded px-3 py-2">
                    </div>
                @endforeach
            </div>
        </section>

        <button class="bg-black text-voom font-semibold rounded px-6 py-2">Enregistrer</button>
    </form>
@endsection
