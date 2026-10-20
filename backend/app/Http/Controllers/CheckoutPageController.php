<?php

namespace App\Http\Controllers;

use App\Enums\PaymentMethod;
use App\Enums\PaymentStatus;
use App\Models\Payment;
use App\Services\Payments\KkiapayGateway;
use App\Services\Payments\PaymentService;
use Illuminate\Http\Request;
use Illuminate\View\View;

/** Page de paiement sécurisée ouverte depuis l'app (lien à usage unique via le jeton du paiement). */
class CheckoutPageController extends Controller
{
    public function __construct(private readonly PaymentService $payments) {}

    public function show(string $token, KkiapayGateway $kkiapay): View
    {
        $payment = Payment::where('checkout_token', $token)->whereIn('gateway', ['kkiapay', 'simulation'])->firstOrFail();

        return view('pay.checkout', [
            'payment' => $payment->load('delivery'),
            'simulation' => $payment->gateway === 'simulation',
            'publicKey' => $kkiapay->publicKey(),
            'sandbox' => $kkiapay->isSandbox(),
            'phone' => preg_replace('/\D/', '', (string) $payment->payer_phone),
            'widgetMethod' => $payment->method === PaymentMethod::Card ? 'card' : 'momo',
            'feeLabel' => config('payments.kkiapay.fee_label'),
        ]);
    }

    /** Mode simulation : le testeur choisit le résultat (aucun argent débité). */
    public function simulate(Request $request, string $token): View
    {
        $payment = Payment::where('checkout_token', $token)->where('gateway', 'simulation')->firstOrFail();

        $this->payments->simulate($payment, $request->input('result') === 'success');

        return $this->resultView($payment->refresh());
    }

    /** Retour du widget après paiement : rattache la transaction puis la vérifie côté serveur. */
    public function return(Request $request, string $token): View
    {
        $payment = Payment::where('checkout_token', $token)->where('gateway', 'kkiapay')->firstOrFail();

        $transactionId = (string) $request->query('transaction_id', '');
        if ($transactionId !== '') {
            $this->payments->attachReference($payment, $transactionId);
        }

        return $this->resultView($this->payments->refresh($payment->refresh()));
    }

    private function resultView(Payment $payment): View
    {
        return view('pay.checkout', [
            'payment' => $payment->load('delivery'),
            'result' => $payment->status === PaymentStatus::Verified ? 'success'
                : ($payment->status === PaymentStatus::Pending ? 'pending' : 'failed'),
        ]);
    }
}
