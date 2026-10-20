<?php

namespace App\Services\Payments;

use App\Enums\PaymentMethod;
use App\Models\Payment;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * KKiaPay — formule « Intégration » : 1,9 % à la charge du payeur (+ abonnement mensuel).
 *
 * Le client paie dans le widget officiel KKiaPay (page /paiement/{token} servie par l'API),
 * en mobile money ou par carte, puis le serveur vérifie la transaction via l'API privée de KKiaPay.
 */
class KkiapayGateway implements PaymentGateway
{
    public function name(): string
    {
        return 'kkiapay';
    }

    public function isConfigured(): bool
    {
        return filled(config('payments.kkiapay.public_key'))
            && filled(config('payments.kkiapay.private_key'))
            && filled(config('payments.kkiapay.secret'));
    }

    public function methods(): array
    {
        return [PaymentMethod::Flooz, PaymentMethod::Mixx, PaymentMethod::Card];
    }

    public function start(Payment $payment): array
    {
        return [
            'mode' => 'redirect',
            'redirect_url' => route('checkout.show', $payment->checkout_token),
            'message' => 'Finalisez le paiement sur la page sécurisée KKiaPay.',
        ];
    }

    public function check(Payment $payment): ?bool
    {
        // L'identifiant KKiaPay n'est connu qu'après le paiement dans le widget (retour ou webhook).
        if (! $payment->gateway_reference) {
            return null;
        }

        $response = Http::withHeaders([
            'X-API-KEY' => config('payments.kkiapay.public_key'),
            'X-PRIVATE-KEY' => config('payments.kkiapay.private_key'),
            'X-SECRET-KEY' => config('payments.kkiapay.secret'),
        ])
            ->acceptJson()
            ->timeout(20)
            ->post($this->baseUrl().'/api/v1/transactions/status', ['transactionId' => $payment->gateway_reference]);

        if ($response->failed()) {
            Log::warning('KKiaPay: vérification impossible', ['payment' => $payment->id, 'http' => $response->status()]);

            return $response->status() === 404 ? false : null;
        }

        return match ($response->json('status')) {
            'SUCCESS' => $this->amountMatches($payment, (int) $response->json('amount')),
            'PENDING' => null,
            default => false,
        };
    }

    public function publicKey(): ?string
    {
        return config('payments.kkiapay.public_key');
    }

    public function isSandbox(): bool
    {
        return (bool) config('payments.kkiapay.sandbox');
    }

    private function amountMatches(Payment $payment, int $paid): bool
    {
        if ($paid < $payment->amount) {
            Log::error('KKiaPay: montant payé insuffisant', ['payment' => $payment->id, 'paid' => $paid, 'expected' => $payment->amount]);

            return false;
        }

        return true;
    }

    private function baseUrl(): string
    {
        return $this->isSandbox() ? 'https://api-sandbox.kkiapay.me' : 'https://api.kkiapay.me';
    }
}
