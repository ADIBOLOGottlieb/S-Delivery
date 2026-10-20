<?php

namespace App\Services\Payments;

use App\Enums\PaymentMethod;
use App\Models\Payment;

/**
 * Mode simulation (démonstration, tests) : aucun argent n'est débité.
 * Le client choisit « paiement réussi » ou « échec » sur la page /paiement/{token}.
 * À activer uniquement pendant les tests (Admin › Réglages › Mode de paiement).
 */
class SimulationGateway implements PaymentGateway
{
    public function name(): string
    {
        return 'simulation';
    }

    public function isConfigured(): bool
    {
        return true;
    }

    public function methods(): array
    {
        return PaymentMethod::cases();
    }

    public function start(Payment $payment): array
    {
        return [
            'mode' => 'redirect',
            'redirect_url' => route('checkout.show', $payment->checkout_token),
            'message' => 'Mode test : choisissez le résultat du paiement sur la page de simulation.',
        ];
    }

    /** Le résultat est fixé directement par la page de simulation. */
    public function check(Payment $payment): ?bool
    {
        return null;
    }
}
