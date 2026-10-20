<?php

namespace App\Services\Payments;

use App\Enums\PaymentMethod;
use App\Models\Payment;

/** Agrégateur de paiement (mobile money Flooz / Mixx by Yas, carte bancaire selon l'agrégateur). */
interface PaymentGateway
{
    /** Nom technique stocké dans payments.gateway (kkiapay, paygate, simulation). */
    public function name(): string;

    /** Les clés nécessaires sont-elles configurées ? */
    public function isConfigured(): bool;

    /** @return list<PaymentMethod> moyens acceptés par cet agrégateur */
    public function methods(): array;

    /**
     * Lance le paiement auprès de l'agrégateur.
     *
     * @return array{mode: 'ussd'|'redirect', message: string, redirect_url?: string}
     *
     * @throws \Illuminate\Validation\ValidationException si l'agrégateur refuse la demande
     */
    public function start(Payment $payment): array;

    /**
     * Interroge l'agrégateur : true = payé, false = échoué / expiré, null = toujours en attente.
     * C'est la seule source de vérité : les webhooks ne font que déclencher cette vérification.
     */
    public function check(Payment $payment): ?bool;
}
