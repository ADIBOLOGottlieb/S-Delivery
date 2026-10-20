<?php

namespace App\Services\Payments;

use App\Enums\PaymentMethod;
use App\Models\Payment;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;

/**
 * PayGate Global (Togo) — 2,5 % Flooz / 3 % Mixx by Yas, sans abonnement.
 *
 * Paiement « push » : le client reçoit une demande sur son téléphone et valide avec son code PIN.
 */
class PaygateGateway implements PaymentGateway
{
    public function name(): string
    {
        return 'paygate';
    }

    public function isConfigured(): bool
    {
        return filled(config('payments.paygate.auth_token'));
    }

    public function methods(): array
    {
        return PaymentMethod::mobileMoney();
    }

    public function start(Payment $payment): array
    {
        $response = $this->post('/api/v1/pay', [
            'phone_number' => $this->localNumber($payment->payer_phone),
            'amount' => $payment->amount,
            'description' => 'S-Delivery '.$payment->delivery->reference,
            'identifier' => $payment->checkout_token,
            'network' => $payment->method === PaymentMethod::Flooz ? 'FLOOZ' : 'TMONEY',
        ]);

        $status = (int) $response->json('status', -1);
        if ($response->failed() || $status !== 0) {
            Log::warning('PayGate: demande refusée', ['payment' => $payment->id, 'http' => $response->status(), 'status' => $status]);

            throw ValidationException::withMessages(['payment' => match ($status) {
                4 => 'Numéro ou montant invalide pour ce moyen de paiement.',
                6 => 'Une demande identique est déjà en cours.',
                default => 'Le service de paiement est momentanément indisponible. Réessayez.',
            }]);
        }

        $payment->forceFill(['gateway_reference' => (string) $response->json('tx_reference')])->save();

        return [
            'mode' => 'ussd',
            'message' => 'Une demande de paiement a été envoyée sur votre téléphone. Validez-la avec votre code secret '
                .($payment->method === PaymentMethod::Flooz ? 'Flooz.' : 'Mixx by Yas.'),
        ];
    }

    public function check(Payment $payment): ?bool
    {
        $response = $this->post('/api/v2/status', ['identifier' => $payment->checkout_token]);

        if ($response->failed()) {
            return null;
        }

        return match ((int) $response->json('status', 2)) {
            0 => true,      // paiement réussi
            4, 6 => false,  // expiré, annulé
            default => null, // 2 = en cours
        };
    }

    private function post(string $path, array $data)
    {
        return Http::acceptJson()
            ->timeout(30)
            ->post(rtrim(config('payments.paygate.base_url'), '/').$path, [
                'auth_token' => config('payments.paygate.auth_token'),
                ...$data,
            ]);
    }

    /** PayGate attend le numéro local à 8 chiffres (sans indicatif 228). */
    private function localNumber(string $phone): string
    {
        $digits = preg_replace('/\D/', '', $phone);

        return strlen($digits) > 8 && str_starts_with($digits, '228') ? substr($digits, 3) : $digits;
    }
}
