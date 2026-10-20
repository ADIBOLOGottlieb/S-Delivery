<?php

namespace App\Http\Controllers\Api;

use App\Enums\PaymentMethod;
use App\Http\Controllers\Controller;
use App\Http\Resources\DeliveryResource;
use App\Http\Resources\PaymentResource;
use App\Models\Delivery;
use App\Models\Payment;
use App\Services\Payments\PaymentService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** Paiement intégré d'une livraison via l'agrégateur (Flooz, Mixx by Yas, carte). */
class CheckoutController extends Controller
{
    public function __construct(private readonly PaymentService $payments) {}

    public function store(Request $request, Delivery $delivery): JsonResponse
    {
        abort_unless($delivery->client_id === $request->user()->id, 404);

        $data = $request->validate([
            'method' => ['required', Rule::enum(PaymentMethod::class)],
            'phone' => ['required', 'string', 'max:30', 'regex:/^\+?[0-9 ]{8,15}$/'],
        ], [
            'phone.required' => 'Indiquez le numéro qui va payer.',
            'phone.regex' => 'Numéro de téléphone invalide.',
        ]);

        $result = $this->payments->checkout($delivery, PaymentMethod::from($data['method']), $data['phone']);

        return response()->json([
            'payment' => new PaymentResource($result['payment']),
            'mode' => $result['mode'],
            'message' => $result['message'],
            'redirect_url' => $result['redirect_url'] ?? null,
        ], 201);
    }

    /** Interrogé régulièrement par l'app pendant que le client valide le paiement. */
    public function show(Request $request, Delivery $delivery, Payment $payment): JsonResponse
    {
        abort_unless($delivery->client_id === $request->user()->id && $payment->delivery_id === $delivery->id, 404);

        $payment = $this->payments->refresh($payment);

        return response()->json([
            'payment' => new PaymentResource($payment),
            'delivery' => new DeliveryResource($delivery->refresh()->load(DeliveryController::RELATIONS)),
        ]);
    }
}
