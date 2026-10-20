<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Paiement · S-Delivery</title>
    <link rel="icon" type="image/png" href="{{ asset('images/s-delivery-icon.png') }}">
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-white min-h-screen flex flex-col items-center px-5 py-10 text-black antialiased">
    <img src="{{ asset('images/s-delivery-logo.png') }}" alt="S-Delivery" class="h-10 mb-10">

    <div class="w-full max-w-sm">
        <p class="text-gray-500 text-sm">Livraison {{ $payment->delivery->reference }}</p>
        <p class="text-4xl font-extrabold tracking-tight mt-1">{{ number_format($payment->amount, 0, ',', ' ') }} FCFA</p>
        <p class="text-gray-500 text-sm mt-1">{{ $payment->method->label() }}</p>

        <div class="mt-8">
        @isset($result)
            @if ($result === 'success')
                <div class="rounded-2xl bg-emerald-50 p-5">
                    <p class="font-bold text-lg">Paiement confirmé</p>
                    <p class="text-gray-600 mt-1">Retournez dans l'application S-Delivery : votre livreur va être assigné.</p>
                </div>
            @elseif ($result === 'pending')
                <div class="rounded-2xl bg-amber-50 p-5">
                    <p class="font-bold text-lg">Vérification en cours</p>
                    <p class="text-gray-600 mt-1">Retournez dans l'application : la confirmation s'affichera automatiquement.</p>
                </div>
            @else
                <div class="rounded-2xl bg-red-50 p-5">
                    <p class="font-bold text-lg">Paiement non abouti</p>
                    <p class="text-gray-600 mt-1">Aucun montant n'a été validé. Retournez dans l'application pour réessayer.</p>
                </div>
            @endif
        @else
            @if ($payment->status->value !== 'pending')
                <p class="text-gray-700">Ce lien de paiement n'est plus valide. Retournez dans l'application.</p>
            @elseif ($simulation)
                <p class="rounded-xl bg-amber-100 text-amber-900 text-sm p-3 font-semibold">
                    MODE SIMULATION — aucun argent n'est débité.
                </p>
                <form method="POST" action="{{ route('checkout.simulate', $payment->checkout_token) }}" class="mt-6 space-y-3">
                    @csrf
                    <button name="result" value="success" class="w-full bg-black text-white font-semibold rounded-xl py-4">
                        Simuler un paiement réussi
                    </button>
                    <button name="result" value="fail" class="w-full bg-gray-100 text-black font-semibold rounded-xl py-4">
                        Simuler un échec
                    </button>
                </form>
            @else
                <p class="text-gray-500 text-sm">{{ $feeLabel }}</p>
                <button id="pay" class="mt-6 w-full bg-black text-white font-semibold rounded-xl py-4">
                    Payer maintenant
                </button>
                <p class="text-xs text-gray-400 mt-4 text-center">Paiement sécurisé par KKiaPay</p>
            @endif
        @endisset
        </div>
    </div>

    @if (! isset($result) && empty($simulation) && $payment->status->value === 'pending')
        <script src="https://cdn.kkiapay.me/k.js"></script>
        <script>
            const returnUrl = @json(route('checkout.return', $payment->checkout_token));
            function pay() {
                openKkiapayWidget({
                    amount: @json($payment->amount),
                    key: @json($publicKey),
                    sandbox: @json($sandbox),
                    phone: @json($phone),
                    data: @json($payment->checkout_token),
                    paymentmethod: @json($widgetMethod),
                    countries: ['TG'],
                    theme: '#000000',
                    position: 'center',
                });
            }
            addSuccessListener(response => {
                window.location.href = returnUrl + '?transaction_id=' + encodeURIComponent(response.transactionId);
            });
            document.getElementById('pay').addEventListener('click', pay);
            window.addEventListener('load', pay);
        </script>
    @endif
</body>
</html>
