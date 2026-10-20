<?php

namespace App\Http\Controllers\Admin;

use App\Enums\DeliveryStatus;
use App\Enums\PaymentMethod;
use App\Enums\PaymentStatus;
use App\Http\Controllers\Controller;
use App\Models\Delivery;
use App\Models\Payment;
use App\Models\User;
use App\Services\DeliveryReminder;
use App\Services\Payments\PaymentService;
use App\Services\PushNotifier;
use Illuminate\Support\Str;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Illuminate\View\View;
use Symfony\Component\HttpFoundation\Response;

class DeliveryController extends Controller
{
    public function __construct(private readonly DeliveryReminder $notifier) {}

    public function dashboard(): View
    {
        return view('admin.dashboard', [
            'paymentsToReview' => Delivery::where('payment_status', PaymentStatus::Submitted)->count(),
            'toAssign' => Delivery::where('status', DeliveryStatus::Pending)
                ->where('payment_status', PaymentStatus::Verified)->count(),
            'inProgress' => Delivery::whereIn('status', [DeliveryStatus::Assigned, DeliveryStatus::PickedUp])->count(),
            'deliveredToday' => Delivery::where('status', DeliveryStatus::Delivered)
                ->whereDate('delivered_at', today())->count(),
            'activeCouriers' => User::couriers()->where('is_active', true)->count(),
            // Frais de livraison réellement gagnés : courses livrées ce mois et payées (hors montant des articles).
            'revenueMonth' => (int) Delivery::where('status', DeliveryStatus::Delivered)
                ->where('payment_status', PaymentStatus::Verified)
                ->whereBetween('delivered_at', [now()->startOfMonth(), now()])
                ->sum('delivery_fee'),
            'latest' => Delivery::with(['client', 'courier'])->latest()->limit(8)->get(),
        ]);
    }

    public function index(Request $request): View
    {
        $filters = $request->validate([
            'status' => ['nullable', Rule::enum(DeliveryStatus::class)],
            'payment_status' => ['nullable', Rule::enum(PaymentStatus::class)],
            'search' => ['nullable', 'string', 'max:100'],
        ]);

        $deliveries = Delivery::query()
            ->with(['client', 'courier'])
            ->when($filters['status'] ?? null, fn ($q, $s) => $q->where('status', $s))
            ->when($filters['payment_status'] ?? null, fn ($q, $s) => $q->where('payment_status', $s))
            ->when($filters['search'] ?? null, function ($q, $s) {
                // Insensible à la casse ; % et _ tapés par l'admin sont cherchés tels quels, pas comme jokers.
                $q->where(fn ($q) => $q
                    ->whereContains('deliveries.reference', $s)
                    ->orWhereContains('deliveries.recipient_phone', $s)
                    ->orWhereHas('client', fn ($q) => $q
                        ->whereContains('users.name', $s)
                        ->orWhereContains('users.phone_number', $s)));
            })
            ->latest()
            ->paginate(25)
            ->withQueryString();

        return view('admin.deliveries.index', compact('deliveries', 'filters'));
    }

    public function show(Request $request, Delivery $delivery): View
    {
        $delivery->load(['client', 'courier', 'payments.reviewer', 'photos', 'deliveryRequest', 'messages.sender', 'messages.media']);
        $delivery->markReadBy($request->user());

        $couriers = User::couriers()
            ->where('is_active', true)
            ->withCount(['assignedDeliveries as active_count' => fn ($q) => $q
                ->whereIn('status', [DeliveryStatus::Assigned, DeliveryStatus::PickedUp])])
            ->orderBy('name')
            ->get();

        return view('admin.deliveries.show', compact('delivery', 'couriers'));
    }

    public function assign(Request $request, Delivery $delivery): RedirectResponse
    {
        $data = $request->validate(['courier_id' => ['bail', 'required', 'integer', 'exists:users,id']]);

        $before = $delivery->courier_id;
        $previous = $delivery->assignTo(User::findOrFail($data['courier_id']));
        $delivery->load('courier', 'client');

        if ($before !== $delivery->courier_id) {
            $this->notifier->notifyAssigned($delivery);
            $this->notifier->notifyClient($delivery, 'assigned');
        }
        if ($previous) {
            $this->notifier->notifyCourierRemoved($delivery, User::find($previous), 'unassigned');
        }

        return back()->with('success', 'Livreur assigné.');
    }

    /** Réponse de l'agence dans la discussion de la course (prévient le client et le livreur). */
    public function message(Request $request, Delivery $delivery, PushNotifier $push): RedirectResponse
    {
        $data = $request->validate(['body' => ['required', 'string', 'max:2000']]);

        $delivery->post($request->user(), ['body' => trim($data['body'])]);
        $delivery->loadMissing(['client', 'courier']);
        foreach (array_filter([$delivery->client, $delivery->courier]) as $recipient) {
            rescue(fn () => $push->toUser($recipient, 'S-Delivery · '.$delivery->reference, Str::limit($data['body'], 120), [
                'type' => 'delivery_chat',
                'delivery_id' => (string) $delivery->id,
            ]), report: false);
        }

        return back()->with('success', 'Message envoyé.');
    }

    /** Validation du paiement par l'admin (espèces, virement vérifié manuellement, test). */
    public function confirmPayment(Request $request, Delivery $delivery, PaymentService $payments): RedirectResponse
    {
        $data = $request->validate([
            'method' => ['required', Rule::enum(PaymentMethod::class)],
            'reference' => ['nullable', 'string', 'max:100'],
        ]);

        $payments->confirmByAdmin($delivery, $request->user(), PaymentMethod::from($data['method']), $data['reference'] ?? null);
        $this->notifier->notifyClient($delivery->load('client'), 'payment_verified');

        return back()->with('success', 'Paiement validé. Vous pouvez assigner un livreur.');
    }

    public function cancel(Request $request, Delivery $delivery): RedirectResponse
    {
        $data = $request->validate(['reason' => ['required', 'string', 'max:255']]);

        $delivery->cancel($data['reason']);
        $delivery->load('client', 'courier');

        $this->notifier->notifyClient($delivery, 'cancelled', $data['reason']);
        $this->notifier->notifyCourierRemoved($delivery, $delivery->courier, 'cancelled');

        return back()->with('success', $delivery->needsRefund()
            ? 'Livraison annulée. Le client avait payé : remboursez-lui '.number_format($delivery->total_amount, 0, ',', ' ').' FCFA.'
            : 'Livraison annulée.');
    }

    public function approvePayment(Request $request, Payment $payment, PaymentService $payments): RedirectResponse
    {
        $delivery = $payments->approve($payment, $request->user());
        $this->notifier->notifyClient($delivery->load('client'), 'payment_verified');

        return back()->with('success', 'Paiement confirmé. Vous pouvez maintenant assigner un livreur.');
    }

    public function rejectPayment(Request $request, Payment $payment, PaymentService $payments): RedirectResponse
    {
        $data = $request->validate(['rejection_reason' => ['required', 'string', 'max:255']]);

        if (! $payments->reject($payment, $request->user(), $data['rejection_reason'])) {
            return back()->with('success', 'Preuve refusée. Le statut de paiement de la livraison est inchangé.');
        }

        $this->notifier->notifyClient($payment->delivery()->with('client')->firstOrFail(), 'payment_rejected', $data['rejection_reason']);

        return back()->with('success', 'Paiement refusé. Le client peut renvoyer une preuve.');
    }

    /** Capture de la transaction, réservée aux admins (en base ; anciens fichiers encore sur disque). */
    public function screenshot(Payment $payment): Response
    {
        if ($payment->screenshot_media_id && $media = $payment->screenshot) {
            return response($media->bytes(), 200, [
                'Content-Type' => $media->mime,
                'Cache-Control' => 'private, max-age=3600',
                'X-Content-Type-Options' => 'nosniff',
            ]);
        }

        abort_unless($payment->screenshot_path && Storage::disk('local')->exists($payment->screenshot_path), 404);

        return Storage::disk('local')->response($payment->screenshot_path);
    }
}
