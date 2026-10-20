@extends('layouts.admin')

@section('title', 'Réglages')

@section('content')
    <h1 class="text-2xl font-bold mb-4">Réglages</h1>

    <form method="POST" action="{{ route('admin.settings.update') }}" class="space-y-6 max-w-2xl">
        @csrf @method('PUT')

        <section class="bg-white rounded-lg shadow-sm p-6 space-y-4">
            <h2 class="font-semibold">Paiement intégré</h2>

            <div>
                <label class="block text-sm font-medium mb-1" for="payment_mode">Mode de paiement</label>
                <select id="payment_mode" name="payment_mode" class="w-full border rounded px-3 py-2">
                    <option value="auto" @selected(old('payment_mode', $gateway['mode']) === 'auto')>
                        Automatique — paiement dans l'app{{ $gateway['configured'] ? ' ('.$gateway['configured'].')' : ' (clés non configurées → manuel)' }}
                    </option>
                    <option value="manual" @selected(old('payment_mode', $gateway['mode']) === 'manual')>Manuel — virement + capture d'écran vérifiée par l'admin</option>
                    <option value="simulation" @selected(old('payment_mode', $gateway['mode']) === 'simulation')>Simulation — démonstration, aucun argent débité</option>
                </select>
                <p class="text-xs text-gray-500 mt-1">Dans tous les modes, vous pouvez aussi valider un paiement depuis la fiche d'une livraison.</p>
            </div>

            <div class="rounded border p-4 text-sm {{ $gateway['active'] === 'simulation' ? 'bg-orange-50 border-orange-300' : ($gateway['active'] ? 'bg-green-50 border-green-200' : 'bg-gray-50 border-gray-200') }}">
                @if ($gateway['active'] === 'simulation')
                    <p class="font-semibold text-orange-800">⚠ Mode simulation actif : les clients peuvent « payer » sans argent réel.</p>
                    <p class="text-gray-600 mt-1">À utiliser uniquement pour les tests. Repassez en mode Automatique ou Manuel avant l'ouverture au public.</p>
                @elseif ($gateway['active'])
                    <p class="font-semibold text-green-800">
                        Paiement en ligne actif : {{ $gateway['active'] === 'kkiapay' ? 'KKiaPay (Flooz, Mixx by Yas, carte bancaire)' : 'PayGate Global (Flooz, Mixx by Yas)' }}
                        @if ($gateway['active'] === 'kkiapay' && $gateway['sandbox']) <span class="text-orange-700">(mode test / sandbox)</span> @endif
                    </p>
                    <p class="text-gray-600 mt-1">Les clients paient dans l'app ; le paiement est confirmé automatiquement.</p>
                @else
                    <p class="font-semibold text-gray-800">Mode manuel : virement sur les numéros ci-dessous + capture d'écran à vérifier.</p>
                    @if ($gateway['mode'] === 'auto' && $gateway['requested'] !== 'manual')
                        <p class="text-gray-600 mt-1">« {{ $gateway['requested'] }} » est demandé mais ses clés sont absentes des variables d'environnement.</p>
                    @endif
                @endif
                <p class="text-gray-500 mt-2">Agrégateur et clés : variables <code>PAYMENT_GATEWAY</code>, <code>KKIAPAY_*</code> / <code>PAYGATE_AUTH_TOKEN</code> (voir le README).</p>
                <p class="text-gray-500">URL de notification à déclarer : KKiaPay <code class="break-all">{{ $gateway['webhook_kkiapay'] }}</code> · PayGate <code class="break-all">{{ $gateway['webhook_paygate'] }}</code></p>
            </div>

            <p class="text-sm text-gray-500">
                Numéros marchands (mode manuel, ou repli si le paiement en ligne est indisponible) : le client vire le montant
                puis envoie la capture d'écran ; vous confirmez depuis la fiche de la livraison.
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
                <label class="block text-sm font-medium mb-1">Numéro de l'agence <span class="text-gray-500 font-normal">(bouton « Contacter l'agence » de l'app)</span></label>
                <input name="support_phone" value="{{ old('support_phone', $settings['support_phone']) }}" placeholder="+228 90 00 00 00" class="w-full border rounded px-3 py-2">
            </div>
            <div>
                <label class="block text-sm font-medium mb-1">Email de l'agence <span class="text-gray-500 font-normal">(facultatif, affiché dans la politique de confidentialité)</span></label>
                <input name="support_email" type="email" value="{{ old('support_email', $settings['support_email']) }}" placeholder="contact@exemple.tg" class="w-full border rounded px-3 py-2">
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

        <button class="bg-black text-brand font-semibold rounded px-6 py-2">Enregistrer</button>
    </form>
@endsection
