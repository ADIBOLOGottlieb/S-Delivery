<?php

namespace App\Http\Controllers\Api;

use App\Enums\DeliveryStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\DeliveryResource;
use App\Models\Delivery;
use App\Services\DeliveryReminder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;

/** Livraisons assignées au livreur connecté. */
class CourierDeliveryController extends Controller
{
    private const RELATIONS = ['client', 'photos', 'deliveryRequest'];

    /** ?scope=active (par défaut : assignées / récupérées) ou ?scope=history (terminées). */
    public function index(Request $request): AnonymousResourceCollection
    {
        $active = [DeliveryStatus::Assigned, DeliveryStatus::PickedUp];

        $query = $request->user()->assignedDeliveries()->with(self::RELATIONS);

        if ($request->query('scope') === 'history') {
            $query->whereNotIn('status', $active)->latest('updated_at');
        } else {
            $query->whereIn('status', $active)->orderBy('assigned_at');
        }

        return DeliveryResource::collection($query->paginate(30));
    }

    public function show(Request $request, Delivery $delivery): DeliveryResource
    {
        $this->authorizeCourier($request, $delivery);

        return new DeliveryResource($delivery->load(self::RELATIONS));
    }

    /** « Colis récupéré » puis « Livré » (avec le code de remise donné par le destinataire). */
    public function updateStatus(Request $request, Delivery $delivery): DeliveryResource
    {
        $this->authorizeCourier($request, $delivery);

        $data = $request->validate([
            'status' => ['required', Rule::in([DeliveryStatus::PickedUp->value, DeliveryStatus::Delivered->value])],
            'code' => ['nullable', 'string', 'max:10'],
        ]);

        $target = DeliveryStatus::from($data['status']);
        $delivery->advanceByCourier($target, $request->user(), $data['code'] ?? null);

        $delivery->post(null, ['body' => $target === DeliveryStatus::PickedUp
            ? '📦 Colis récupéré par le livreur, en route vers la destination.'
            : '✅ Colis remis au destinataire.']);
        app(DeliveryReminder::class)->notifyClient($delivery, $target === DeliveryStatus::PickedUp ? 'picked_up' : 'delivered');

        return new DeliveryResource($delivery->load(self::RELATIONS));
    }

    /** Position du livreur, envoyée par l'app toutes les ~15 s pendant une course. */
    public function location(Request $request): JsonResponse
    {
        $data = $request->validate([
            'lat' => ['required', 'numeric', 'between:-90,90'],
            'lng' => ['required', 'numeric', 'between:-180,180'],
        ]);

        $request->user()->forceFill([
            'last_lat' => $data['lat'],
            'last_lng' => $data['lng'],
            'located_at' => now(),
        ])->save();

        return response()->json(['ok' => true]);
    }

    private function authorizeCourier(Request $request, Delivery $delivery): void
    {
        abort_unless($delivery->courier_id === $request->user()->id, 404);
    }
}
