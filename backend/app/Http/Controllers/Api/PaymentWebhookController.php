<?php

namespace App\Http\Controllers\Api;

use App\Enums\PaymentStatus;
use App\Http\Controllers\Controller;
use App\Models\Payment;
use App\Services\Payments\PaymentService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

/**
 * Notifications des agrégateurs. Le contenu reçu n'est jamais cru sur parole :
 * il sert uniquement à retrouver le paiement, qui est ensuite revérifié via l'API de l'agrégateur.
 */
class PaymentWebhookController extends Controller
{
    public function __construct(private readonly PaymentService $payments) {}

    public function kkiapay(Request $request): JsonResponse
    {
        $secret = config('payments.kkiapay.webhook_secret');
        if ($secret && ! hash_equals($secret, (string) $request->header('x-kkiapay-secret'))) {
            Log::warning('KKiaPay webhook: secret invalide', ['ip' => $request->ip()]);

            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $transactionId = (string) $request->input('transactionId');
        $payment = ($transactionId !== '' ? Payment::where('gateway', 'kkiapay')->where('gateway_reference', $transactionId)->first() : null)
            ?? $this->findByToken($request->input('stateData'));

        if ($payment && $transactionId !== '') {
            $this->payments->attachReference($payment, $transactionId);
            $this->payments->refresh($payment->refresh());
        }

        return response()->json(['received' => true]);
    }

    public function paygate(Request $request): JsonResponse
    {
        $payment = Payment::where('gateway', 'paygate')
            ->where('checkout_token', (string) $request->input('identifier'))
            ->first();

        if ($payment) {
            $this->payments->refresh($payment);
        }

        return response()->json(['received' => true]);
    }

    /** Le jeton de paiement est transmis au widget KKiaPay dans « data » et revient dans stateData. */
    private function findByToken(mixed $stateData): ?Payment
    {
        $haystack = is_string($stateData) ? $stateData : json_encode($stateData);
        if (! $haystack || ! preg_match('/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i', $haystack, $m)) {
            return null;
        }

        return Payment::where('gateway', 'kkiapay')
            ->where('checkout_token', $m[0])
            ->where('status', PaymentStatus::Pending)
            ->first();
    }
}
