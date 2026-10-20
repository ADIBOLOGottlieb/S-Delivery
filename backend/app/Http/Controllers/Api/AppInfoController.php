<?php

namespace App\Http\Controllers\Api;

use App\Enums\PaymentMethod;
use App\Http\Controllers\Controller;
use App\Models\Setting;
use App\Services\Payments\PaymentService;
use Illuminate\Http\JsonResponse;

/** Informations de l'agence pour l'app : moyens de paiement, contact et liens publics. */
class AppInfoController extends Controller
{
    /**
     * Paiement en ligne (agrégateur) s'il est actif, sinon numéros marchands Flooz / Mixx by Yas
     * pour le virement suivi d'une capture d'écran.
     */
    public function paymentInfo(PaymentService $payments): JsonResponse
    {
        $methods = [];
        foreach (PaymentMethod::mobileMoney() as $method) {
            $number = Setting::get("{$method->value}_merchant_number");
            if ($number) {
                $methods[] = ['method' => $method->value, 'label' => $method->label(), 'merchant_number' => $number];
            }
        }

        $gateway = $payments->gateway();

        return response()->json([
            'merchant_name' => Setting::get('merchant_name'),
            'instructions' => Setting::get('payment_instructions'),
            'support_phone' => Setting::get('support_phone') ?: null,
            'support_email' => Setting::get('support_email') ?: null,
            'methods' => $methods,
            'online' => [
                'enabled' => $gateway !== null,
                'gateway' => $gateway?->name(),
                'simulation' => $gateway?->name() === 'simulation',
                'methods' => $gateway
                    ? array_map(fn (PaymentMethod $m) => ['method' => $m->value, 'label' => $m->label()], $gateway->methods())
                    : [],
            ],
            // Pages publiques exigées par Google Play (URL absolues).
            'privacy_url' => route('legal.privacy'),
            'account_deletion_url' => route('legal.account-deletion'),
        ]);
    }
}
