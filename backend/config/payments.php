<?php

/*
| Paiement intégré (Flooz, Mixx by Yas, carte bancaire) via agrégateur.
|
| PAYMENT_GATEWAY :
|   - kkiapay : 1,9 % (payés par le client) + abonnement mensuel — mobile money ET carte bancaire.
|   - paygate : 2,5 % Flooz / 3 % Mixx (payés par l'agence), sans abonnement — demande poussée sur le téléphone.
|   - manual  : virement sur le numéro marchand + capture d'écran vérifiée par l'admin (sans agrégateur).
|
| Sans clés configurées, l'app repasse automatiquement en mode manuel.
| Les clés sont secrètes : uniquement dans .env / variables Render, jamais dans le dépôt.
*/

return [
    'gateway' => env('PAYMENT_GATEWAY', 'manual'),

    'kkiapay' => [
        'public_key' => env('KKIAPAY_PUBLIC_KEY'),
        'private_key' => env('KKIAPAY_PRIVATE_KEY'),
        'secret' => env('KKIAPAY_SECRET'),
        'sandbox' => (bool) env('KKIAPAY_SANDBOX', true),
        // Valeur de l'en-tête x-kkiapay-secret configurée dans le tableau de bord KKiaPay (facultatif).
        'webhook_secret' => env('KKIAPAY_WEBHOOK_SECRET'),
        'fee_label' => '1,9 % de frais de service à la charge du payeur',
    ],

    'paygate' => [
        'auth_token' => env('PAYGATE_AUTH_TOKEN'),
        'base_url' => env('PAYGATE_BASE_URL', 'https://paygateglobal.com'),
    ],
];
