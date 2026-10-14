<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Product;
use App\Models\Promotion;
use App\Services\PushNotifier;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use App\Support\StoredImage;
use Illuminate\View\View;

/** Annonces promotionnelles : bandeaux dans l'app + notification push aux clients. */
class PromotionController extends Controller
{
    public function index(PushNotifier $push): View
    {
        return view('admin.promotions.index', [
            'promotions' => Promotion::with('product')->latest()->paginate(20),
            'pushReady' => $push->isConfigured(),
        ]);
    }

    public function create(): View
    {
        return view('admin.promotions.form', ['promotion' => new Promotion(['is_active' => true]), 'products' => $this->products()]);
    }

    public function store(Request $request): RedirectResponse
    {
        $promotion = Promotion::create($this->validated($request));

        return redirect()->route('admin.promotions.index')
            ->with('success', $this->maybePush($request, $promotion) ?? 'Annonce créée.');
    }

    public function edit(Promotion $promotion): View
    {
        return view('admin.promotions.form', ['promotion' => $promotion, 'products' => $this->products()]);
    }

    public function update(Request $request, Promotion $promotion): RedirectResponse
    {
        $data = $this->validated($request);
        if (isset($data['image_path'])) {
            StoredImage::delete($promotion->image_path);
        }
        $promotion->update($data);

        return redirect()->route('admin.promotions.index')
            ->with('success', $this->maybePush($request, $promotion) ?? 'Annonce mise à jour.');
    }

    public function destroy(Promotion $promotion): RedirectResponse
    {
        StoredImage::delete($promotion->image_path);
        $promotion->delete();

        return back()->with('success', 'Annonce supprimée.');
    }

    /** Envoi (ou renvoi) de l'annonce en notification push à tous les clients. */
    public function push(Promotion $promotion, PushNotifier $push): RedirectResponse
    {
        return back()->with('success', $this->sendPush($promotion, $push));
    }

    private function maybePush(Request $request, Promotion $promotion): ?string
    {
        return $request->boolean('send_push') ? $this->sendPush($promotion, app(PushNotifier::class)) : null;
    }

    private function sendPush(Promotion $promotion, PushNotifier $push): string
    {
        if (! $promotion->isVisible()) {
            return "Annonce enregistrée, mais non envoyée : elle n'est pas active aujourd'hui.";
        }
        if (! $push->isConfigured()) {
            return "Annonce visible dans l'app. Notification non envoyée : Firebase n'est pas encore configuré (voir README).";
        }

        $ok = $push->toTopic(PushNotifier::TOPIC_CLIENTS, $promotion->title, $promotion->body, array_filter([
            'kind' => 'promotion',
            'promotion_id' => (string) $promotion->id,
            'product_id' => $promotion->product_id ? (string) $promotion->product_id : null,
        ]));

        if ($ok) {
            $promotion->forceFill(['pushed_at' => now()])->save();
        }

        return $ok ? 'Notification envoyée à tous les clients.' : "L'envoi de la notification a échoué (voir les journaux).";
    }

    /** @return array<string, mixed> */
    private function validated(Request $request): array
    {
        $data = $request->validate([
            'title' => ['required', 'string', 'max:80'],
            'body' => ['required', 'string', 'max:255'],
            'product_id' => ['nullable', 'exists:products,id'],
            'starts_at' => ['nullable', 'date'],
            'ends_at' => ['nullable', 'date', 'after_or_equal:starts_at'],
            'image' => ['nullable', 'image', 'max:4096'],
        ]);

        if ($request->hasFile('image')) {
            $data['image_path'] = StoredImage::store($request->file('image'));
        }
        unset($data['image']);

        return [...$data, 'is_active' => $request->boolean('is_active')];
    }

    private function products()
    {
        return Product::where('is_active', true)->orderBy('type', 'desc')->orderBy('name')->get(['id', 'name', 'type']);
    }
}
