<?php

namespace App\Http\Controllers\Admin;

use App\Enums\DeliveryType;
use App\Http\Controllers\Controller;
use App\Models\Delivery;
use App\Models\DeliveryRequest;
use App\Models\Media;
use App\Services\PricingService;
use App\Services\PushNotifier;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\View\View;

/** Demandes rapides des clients habitués : discussion puis programmation de la livraison. */
class RequestController extends Controller
{
    public function __construct(private readonly PushNotifier $push) {}

    /** Demandes dont le dernier message n'a pas été lu par l'agence. */
    public static function unreadCount(): int
    {
        return DeliveryRequest::query()
            ->where('status', DeliveryRequest::OPEN)
            ->whereNotNull('last_message_id')
            ->where(fn ($q) => $q->whereNull('admin_read_id')->orWhereColumn('last_message_id', '>', 'admin_read_id'))
            ->count();
    }

    public function index(Request $request): View
    {
        $status = $request->query('status', DeliveryRequest::OPEN);

        $requests = DeliveryRequest::query()
            ->with(['client', 'latestMessage', 'delivery'])
            ->when($status !== 'all', fn ($q) => $q->where('status', $status))
            ->orderByDesc('last_message_at')
            ->paginate(25)
            ->withQueryString();

        return view('admin.requests.index', compact('requests', 'status'));
    }

    public function show(DeliveryRequest $deliveryRequest): View
    {
        $deliveryRequest->load(['client', 'messages.media', 'messages.sender', 'delivery']);
        $deliveryRequest->markReadByAdmin();

        // Dernière livraison du client : pré-remplit le point A (souvent sa boutique).
        $previous = Delivery::where('client_id', $deliveryRequest->client_id)->latest()->first();

        return view('admin.requests.show', ['request' => $deliveryRequest, 'previous' => $previous]);
    }

    public function reply(Request $request, DeliveryRequest $deliveryRequest): RedirectResponse
    {
        $data = $request->validate([
            'body' => ['nullable', 'required_without:photo', 'string', 'max:2000'],
            'photo' => ['nullable', 'image', 'max:5120'],
        ]);

        $deliveryRequest->post($request->user(), [
            'body' => $data['body'] ?? null,
            'media_id' => $request->hasFile('photo') ? Media::fromUpload($request->file('photo'))->id : null,
        ]);

        $this->notifyClient($deliveryRequest, $data['body'] ?? '📷 Photo');

        return redirect()->route('admin.requests.show', $deliveryRequest);
    }

    /** Crée la livraison à partir de la discussion ; le client n'a plus qu'à payer. */
    public function schedule(Request $request, DeliveryRequest $deliveryRequest, PricingService $pricing): RedirectResponse
    {
        abort_if($deliveryRequest->delivery_id !== null, 422, 'Une livraison est déjà programmée pour cette demande.');

        $data = $request->validate([
            'type' => ['required', Rule::enum(DeliveryType::class)],
            'pickup_address' => ['required', 'string', 'max:255'],
            'pickup_lat' => ['required', 'numeric', 'between:-90,90'],
            'pickup_lng' => ['required', 'numeric', 'between:-180,180'],
            'pickup_contact_name' => ['nullable', 'string', 'max:255'],
            'pickup_contact_phone' => ['nullable', 'string', 'max:30'],
            'dropoff_address' => ['required', 'string', 'max:255'],
            'dropoff_lat' => ['required', 'numeric', 'between:-90,90'],
            'dropoff_lng' => ['required', 'numeric', 'between:-180,180'],
            'recipient_name' => ['required', 'string', 'max:255'],
            'recipient_phone' => ['required', 'string', 'max:30'],
            'package_description' => ['nullable', 'string', 'max:1000'],
            'notes' => ['nullable', 'string', 'max:1000'],
            'scheduled_at' => ['nullable', 'required_if:type,programmee', 'date', 'after:now'],
            'deadline_at' => ['nullable', 'date', 'after:now'],
            // Vide = tarif calculé selon la distance ; sinon prix convenu dans la discussion.
            'delivery_fee' => ['nullable', 'integer', 'min:0', 'max:1000000'],
            // Saisi par l'admin (le client n'envoie qu'une photo) ; rappelé au livreur dans les instructions.
            'parcel_amount' => ['nullable', 'integer', 'min:0', 'max:100000000'],
        ]);

        $type = DeliveryType::from($data['type']);
        $quote = $pricing->quote($type, $data['pickup_lat'], $data['pickup_lng'], $data['dropoff_lat'], $data['dropoff_lng']);
        $fee = $data['delivery_fee'] ?? $quote['delivery_fee'];
        $parcelAmount = $data['parcel_amount'] ?? null;
        unset($data['delivery_fee'], $data['parcel_amount']);

        if ($parcelAmount) {
            $line = 'Montant total du colis : '.number_format($parcelAmount, 0, ',', ' ').' FCFA';
            $data['notes'] = trim($line."\n".($data['notes'] ?? ''));
        }
        $deliveryRequest->forceFill([
            'district' => $deliveryRequest->district ?? $data['dropoff_address'],
            'recipient_phone' => $deliveryRequest->recipient_phone ?? $data['recipient_phone'],
            'parcel_amount' => $parcelAmount ?? $deliveryRequest->parcel_amount,
        ]);

        $delivery = DB::transaction(function () use ($deliveryRequest, $data, $quote, $fee) {
            $delivery = $deliveryRequest->client->deliveries()->create([
                ...$data,
                'distance_km' => $quote['distance_km'],
                'delivery_fee' => $fee,
                'items_amount' => 0,
                'total_amount' => $fee,
            ]);

            // Les photos envoyées dans la discussion accompagnent la livraison (visibles par le livreur).
            $delivery->photos()->attach($deliveryRequest->messages()->whereNotNull('media_id')->pluck('media_id'));

            $deliveryRequest->forceFill(['delivery_id' => $delivery->id, 'status' => DeliveryRequest::SCHEDULED])->save();
            $deliveryRequest->post(null, [
                'body' => "Livraison {$delivery->reference} programmée : ".number_format($fee, 0, ',', ' ')
                    ." FCFA. Payez depuis l'app pour la confirmer.",
            ]);
            $deliveryRequest->markReadByAdmin();

            return $delivery;
        });

        $this->notifyClient($deliveryRequest, "Livraison {$delivery->reference} programmée. Touchez pour payer.");

        return redirect()->route('admin.requests.show', $deliveryRequest)
            ->with('success', "Livraison {$delivery->reference} créée. Le client a été prévenu.");
    }

    public function close(DeliveryRequest $deliveryRequest): RedirectResponse
    {
        $deliveryRequest->forceFill(['status' => DeliveryRequest::CLOSED, 'admin_read_id' => $deliveryRequest->last_message_id])->save();

        return redirect()->route('admin.requests.index')->with('success', 'Demande clôturée.');
    }

    private function notifyClient(DeliveryRequest $deliveryRequest, string $body): void
    {
        $this->push->toUser($deliveryRequest->client, 'VOOM Delivery', $body, [
            'type' => 'chat',
            'request_id' => (string) $deliveryRequest->id,
        ]);
    }
}
