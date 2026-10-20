<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\DeliveryMessageResource;
use App\Models\Delivery;
use App\Models\Media;
use App\Models\User;
use App\Services\PushNotifier;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Throwable;

/**
 * Discussion d'une course entre le client, le livreur assigné et l'agence :
 * texte, photo ou position partagée. Chaque message prévient les autres participants.
 */
class DeliveryChatController extends Controller
{
    public function __construct(private readonly PushNotifier $push) {}

    public function clientIndex(Request $request, Delivery $delivery): AnonymousResourceCollection
    {
        abort_unless($delivery->client_id === $request->user()->id, 404);

        return $this->index($request, $delivery);
    }

    public function clientStore(Request $request, Delivery $delivery): JsonResponse
    {
        abort_unless($delivery->client_id === $request->user()->id, 404);

        return $this->store($request, $delivery);
    }

    public function courierIndex(Request $request, Delivery $delivery): AnonymousResourceCollection
    {
        abort_unless($delivery->courier_id === $request->user()->id, 404);

        return $this->index($request, $delivery);
    }

    public function courierStore(Request $request, Delivery $delivery): JsonResponse
    {
        abort_unless($delivery->courier_id === $request->user()->id, 404);

        return $this->store($request, $delivery);
    }

    /** Messages de la course (les 200 derniers), marqués comme lus. */
    private function index(Request $request, Delivery $delivery): AnonymousResourceCollection
    {
        $delivery->markReadBy($request->user());

        $messages = $delivery->messages()->with(['media', 'sender'])->reorder('id', 'desc')->limit(200)->get()->reverse()->values();
        $messages->each(fn ($m) => $m->setRelation('delivery', $delivery));

        return DeliveryMessageResource::collection($messages)->additional([
            'chat_open' => $delivery->chatOpenFor($request->user()),
        ]);
    }

    private function store(Request $request, Delivery $delivery): JsonResponse
    {
        $user = $request->user();
        if (! $delivery->chatOpenFor($user)) {
            throw ValidationException::withMessages(['body' => 'Cette discussion est fermée.']);
        }

        $data = $request->validate([
            'body' => ['nullable', 'string', 'max:2000'],
            'photo' => ['nullable', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120'],
            'lat' => ['nullable', 'required_with:lng', 'numeric', 'between:-90,90'],
            'lng' => ['nullable', 'required_with:lat', 'numeric', 'between:-180,180'],
        ]);

        if (blank($data['body'] ?? null) && ! $request->hasFile('photo') && ! isset($data['lat'])) {
            throw ValidationException::withMessages(['body' => 'Message vide.']);
        }

        $message = $delivery->post($user, [
            'body' => filled($data['body'] ?? null) ? trim($data['body']) : null,
            'media_id' => $request->hasFile('photo') ? Media::fromUpload($request->file('photo'))->id : null,
            'lat' => $data['lat'] ?? null,
            'lng' => $data['lng'] ?? null,
        ]);

        $this->notifyOthers($delivery, $user, $message->body ?? ($message->media_id ? '📷 Photo' : '📍 Position partagée'));

        return (new DeliveryMessageResource($message->load(['media', 'sender'])))
            ->response()
            ->setStatusCode(201);
    }

    /** Push vers l'autre partie (client ↔ livreur) ; l'agence lit dans le panneau admin. */
    private function notifyOthers(Delivery $delivery, User $sender, string $preview): void
    {
        $delivery->loadMissing(['client', 'courier']);
        $recipients = collect([$delivery->client, $delivery->courier])
            ->filter(fn (?User $u) => $u !== null && $u->id !== $sender->id);

        $title = match (true) {
            $sender->id === $delivery->courier_id => 'Votre livreur · '.$delivery->reference,
            $sender->id === $delivery->client_id => 'Client · '.$delivery->reference,
            default => 'S-Delivery · '.$delivery->reference,
        };

        foreach ($recipients as $recipient) {
            try {
                $this->push->toUser($recipient, $title, Str::limit($preview, 120), [
                    'type' => 'delivery_chat',
                    'delivery_id' => (string) $delivery->id,
                ]);
            } catch (Throwable $e) {
                Log::warning('Push discussion non envoyé', ['user_id' => $recipient->id, 'error' => $e->getMessage()]);
            }
        }
    }
}
