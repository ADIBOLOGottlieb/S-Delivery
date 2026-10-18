<?php

namespace App\Http\Controllers\Api;

use App\Enums\DeliveryType;
use App\Enums\PaymentMethod;
use App\Http\Controllers\Controller;
use App\Http\Resources\DeliveryResource;
use App\Models\Delivery;
use App\Models\Media;
use App\Models\Product;
use App\Services\Payments\PaymentService;
use App\Services\PricingService;
use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/** Demandes de livraison côté client. */
class DeliveryController extends Controller
{
    private const RELATIONS = ['courier', 'client', 'product', 'latestPayment', 'photos', 'deliveryRequest'];

    private const MAX_PHOTOS = 6;

    public function __construct(private readonly PricingService $pricing) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        $deliveries = $request->user()->deliveries()
            ->with(self::RELATIONS)
            ->latest()
            ->paginate(20);

        return DeliveryResource::collection($deliveries);
    }

    public function quote(Request $request): JsonResponse
    {
        $data = $request->validate([
            'type' => $this->typeRules(),
            ...$this->coordinateRules(),
        ], $this->messages());

        return response()->json($this->pricing->quote(
            DeliveryType::from($data['type']),
            $data['pickup_lat'], $data['pickup_lng'], $data['dropoff_lat'], $data['dropoff_lng'],
        ));
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'type' => $this->typeRules(),
            'product_id' => ['bail', 'nullable', 'integer', Rule::exists('products', 'id')->where('is_active', true)],
            'quantity' => ['required_with:product_id', 'nullable', 'integer', 'min:1', 'max:100'],
            'pickup_address' => ['required_without:product_id', 'nullable', 'string', 'max:255'],
            'pickup_contact_name' => ['nullable', 'string', 'max:255'],
            'pickup_contact_phone' => ['nullable', 'string', 'max:30'],
            'dropoff_address' => ['required', 'string', 'max:255'],
            'recipient_name' => ['required', 'string', 'max:255'],
            'recipient_phone' => ['required', 'string', 'max:30'],
            'package_description' => ['nullable', 'string', 'max:1000'],
            'notes' => ['nullable', 'string', 'max:1000'],
            'scheduled_at' => ['nullable', 'required_if:type,programmee', 'date', 'after:now'],
            // Heure limite de livraison choisie par le client (au moins 30 min pour laisser le temps au livreur).
            'deadline_at' => ['nullable', 'date', 'after:'.now()->addMinutes(29)->toIso8601String(), $this->afterScheduledAt($request)],
            ...$this->coordinateRules(pickupRequired: ! $request->filled('product_id')),
        ], $this->messages());

        $type = DeliveryType::from($data['type']);
        $itemsAmount = 0;

        // Commande marketplace : le point A est le vendeur défini par l'admin (c'est lui que le livreur appelle).
        if (! empty($data['product_id'])) {
            $product = Product::findOrFail($data['product_id']);
            $data['pickup_address'] = $product->pickup_address;
            $data['pickup_lat'] = $product->pickup_lat;
            $data['pickup_lng'] = $product->pickup_lng;
            $data['pickup_contact_name'] = $product->vendor_name;
            $data['pickup_contact_phone'] = $product->vendor_phone;
            $data['package_description'] ??= "{$data['quantity']} × {$product->name}";
            $itemsAmount = $product->price * $data['quantity'];
        }

        $quote = $this->pricing->quote($type, $data['pickup_lat'], $data['pickup_lng'], $data['dropoff_lat'], $data['dropoff_lng']);

        $delivery = $request->user()->deliveries()->create([
            ...$data,
            ...$quote,
            'items_amount' => $itemsAmount,
            'total_amount' => $quote['delivery_fee'] + $itemsAmount,
        ]);

        return (new DeliveryResource($delivery->load(self::RELATIONS)))
            ->response()
            ->setStatusCode(201);
    }

    public function show(Request $request, Delivery $delivery): DeliveryResource
    {
        $this->authorizeOwner($request, $delivery);

        return new DeliveryResource($delivery->load(self::RELATIONS));
    }

    public function cancel(Request $request, Delivery $delivery): DeliveryResource
    {
        $this->authorizeOwner($request, $delivery);

        $delivery->cancelByClient($request->string('reason')->limit(255)->toString() ?: 'Annulée par le client');

        return new DeliveryResource($delivery->load(self::RELATIONS));
    }

    /** Envoi de la preuve de paiement (capture d'écran Flooz / Mixx by Yas). */
    public function submitPayment(Request $request, Delivery $delivery, PaymentService $payments): DeliveryResource
    {
        $this->authorizeOwner($request, $delivery);

        $data = $request->validate([
            'method' => ['required', Rule::enum(PaymentMethod::class)],
            'transaction_ref' => ['required', 'string', 'max:100'],
            'payer_phone' => ['required', 'string', 'max:30'],
            'screenshot' => ['required', 'image', 'max:5120'],
        ]);

        $payments->submitProof(
            $delivery,
            PaymentMethod::from($data['method']),
            $data['transaction_ref'],
            $data['payer_phone'],
            $request->file('screenshot'),
        );

        return new DeliveryResource($delivery->refresh()->load(self::RELATIONS));
    }

    /** Photo d'un article à livrer (aide le livreur à reconnaître le colis). */
    public function addPhoto(Request $request, Delivery $delivery): DeliveryResource
    {
        $this->authorizeOwner($request, $delivery);

        $request->validate(['photo' => ['required', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120']]);

        if (! $delivery->acceptsPhotos()) {
            throw ValidationException::withMessages(['photo' => 'Le colis a déjà été récupéré.']);
        }
        if ($delivery->photos()->count() >= self::MAX_PHOTOS) {
            throw ValidationException::withMessages(['photo' => 'Maximum '.self::MAX_PHOTOS.' photos par livraison.']);
        }

        $delivery->photos()->attach(Media::fromUpload($request->file('photo')));

        return new DeliveryResource($delivery->load(self::RELATIONS));
    }

    private function authorizeOwner(Request $request, Delivery $delivery): void
    {
        abort_unless($delivery->client_id === $request->user()->id, 404);
    }

    /** L'Express a été retiré de l'application (toujours disponible pour l'agence). */
    private function typeRules(): array
    {
        return ['required', Rule::enum(DeliveryType::class), Rule::notIn([DeliveryType::Express->value])];
    }

    /** Heure limite après l'heure de passage, quand les deux sont fournies. */
    private function afterScheduledAt(Request $request): Closure
    {
        return function (string $attribute, mixed $value, Closure $fail) use ($request) {
            $scheduled = strtotime((string) $request->input('scheduled_at'));
            $deadline = strtotime((string) $value);
            if ($request->filled('scheduled_at') && $scheduled && $deadline && $deadline <= $scheduled) {
                $fail("L'heure limite doit être après l'heure de passage programmée.");
            }
        };
    }

    /** @return array<string, string> */
    private function messages(): array
    {
        return [
            'type.required' => 'Choisissez un type de livraison.',
            'type.enum' => 'Type de livraison invalide.',
            'type.not_in' => "La livraison Express n'est plus proposée : choisissez Plis, Colis ou Programmée.",
            'product_id.integer' => "Ce produit n'est plus disponible.",
            'product_id.exists' => "Ce produit n'est plus disponible.",
            'quantity.required_with' => 'Indiquez la quantité.',
            'quantity.integer' => 'La quantité doit être un nombre entier.',
            'quantity.min' => 'La quantité doit être au moins 1.',
            'quantity.max' => 'La quantité ne peut pas dépasser 100.',
            'scheduled_at.required_if' => "Choisissez la date et l'heure de passage.",
            'scheduled_at.date' => 'Date de passage invalide.',
            'scheduled_at.after' => "L'heure de passage doit être dans le futur.",
            'deadline_at.date' => 'Heure limite invalide.',
            'deadline_at.after' => "L'heure limite doit être dans au moins 30 minutes.",
        ];
    }

    /** @return array<string, array<int, string>> */
    private function coordinateRules(bool $pickupRequired = true): array
    {
        $pickup = $pickupRequired ? 'required' : 'nullable';

        return [
            'pickup_lat' => [$pickup, 'numeric', 'between:-90,90'],
            'pickup_lng' => [$pickup, 'numeric', 'between:-180,180'],
            'dropoff_lat' => ['required', 'numeric', 'between:-90,90'],
            'dropoff_lng' => ['required', 'numeric', 'between:-180,180'],
        ];
    }
}
