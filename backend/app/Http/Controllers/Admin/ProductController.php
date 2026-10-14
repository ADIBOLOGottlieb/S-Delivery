<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Product;
use App\Models\Subcategory;
use App\Support\Phone;
use App\Support\StoredImage;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Illuminate\View\View;

/** Gestion des Courses alimentaires : produits et packs, rangés par sous-catégorie (comme dans l'app). */
class ProductController extends Controller
{
    /** Seule catégorie vendue dans l'app (Shopping retiré). */
    private const CATEGORY = 'agro';

    public function index(Request $request): View
    {
        $type = $request->query('type');
        $subcategoryId = $request->integer('subcategory') ?: null;
        // « Autres produits » : produits sans famille, regroupés dans leur propre onglet.
        $others = $request->query('subcategory') === 'others';

        // Sous-onglets identiques à l'app : Tout, les sous-catégories, Autres produits, puis Packs.
        $subcategories = Subcategory::where('category', self::CATEGORY)
            ->withCount('products')
            ->orderBy('position')
            ->get();

        $products = Product::query()
            ->with('subcategory')
            ->where('category', self::CATEGORY)
            ->when($type === 'pack', fn ($q) => $q->where('type', 'pack'))
            ->when($subcategoryId, fn ($q, $id) => $q->where('subcategory_id', $id)->where('type', 'product'))
            ->when($others, fn ($q) => $q->whereNull('subcategory_id')->where('type', 'product'))
            ->latest()
            ->paginate(24)
            ->withQueryString();

        $packsCount = Product::where('category', self::CATEGORY)->where('type', 'pack')->count();
        $othersCount = Product::where('category', self::CATEGORY)->where('type', 'product')->whereNull('subcategory_id')->count();

        return view('admin.products.index', compact('products', 'type', 'subcategories', 'subcategoryId', 'others', 'packsCount', 'othersCount'));
    }

    public function create(Request $request): View
    {
        $isPack = $request->query('type') === 'pack';

        return $this->form(new Product([
            'is_active' => true,
            'category' => self::CATEGORY,
            'type' => $isPack ? 'pack' : 'product',
            'subcategory_id' => $isPack ? null : ($request->integer('subcategory') ?: null),
        ]));
    }

    public function store(Request $request): RedirectResponse
    {
        [$data, $items] = $this->validated($request);
        if ($request->hasFile('image')) {
            $data['image_path'] = StoredImage::store($request->file('image'));
        }

        DB::transaction(function () use ($data, $items) {
            $product = Product::create($data);
            $product->packItems()->sync($product->isPack() ? $items : []);
        });

        return redirect()->route('admin.products.index')->with('success', $data['type'] === 'pack' ? 'Pack créé.' : 'Produit ajouté.');
    }

    public function edit(Product $product): View
    {
        return $this->form($product->load('packItems'));
    }

    public function update(Request $request, Product $product): RedirectResponse
    {
        [$data, $items] = $this->validated($request, $product);
        if ($request->hasFile('image')) {
            StoredImage::delete($product->image_path);
            $data['image_path'] = StoredImage::store($request->file('image'));
        }

        DB::transaction(function () use ($product, $data, $items) {
            $product->update($data);
            $product->packItems()->sync($product->isPack() ? $items : []);
        });

        return redirect()->route('admin.products.index')->with('success', 'Enregistré.');
    }

    public function destroy(Product $product): RedirectResponse
    {
        // Les produits déjà commandés restent liés aux livraisons : on les désactive plutôt que de les supprimer.
        if ($product->getConnection()->table('deliveries')->where('product_id', $product->id)->exists()) {
            $product->update(['is_active' => false]);

            return back()->with('success', 'Déjà commandé : désactivé au lieu d\'être supprimé.');
        }

        StoredImage::delete($product->image_path);
        $product->delete();

        return back()->with('success', 'Supprimé.');
    }

    private function form(Product $product): View
    {
        return view('admin.products.form', [
            'product' => $product,
            'subcategories' => Subcategory::where('category', self::CATEGORY)->orderBy('position')->get(),
            'components' => Product::where('category', self::CATEGORY)->where('type', 'product')->where('is_active', true)
                ->orderBy('name')->get(['id', 'name', 'price', 'unit', 'category']),
        ]);
    }

    /** @return array{0: array<string, mixed>, 1: array<int, array{quantity: int}>} */
    private function validated(Request $request, ?Product $product = null): array
    {
        $data = $request->validate([
            'type' => ['required', Rule::in(['product', 'pack'])],
            'category' => ['required', Rule::in(array_keys(Product::CATEGORIES))],
            'subcategory_id' => ['nullable', Rule::exists('subcategories', 'id')->where('category', $request->input('category'))],
            'name' => ['required', 'string', 'max:255'],
            'description' => ['nullable', 'string', 'max:2000'],
            'price' => ['required', 'integer', 'min:0'],
            'unit' => ['nullable', 'string', 'max:30'],
            'vendor_name' => ['nullable', 'string', 'max:255'],
            'vendor_phone' => ['nullable', 'string', 'max:30'],
            'pickup_address' => ['required', 'string', 'max:255'],
            'pickup_lat' => ['required', 'numeric', 'between:-90,90'],
            'pickup_lng' => ['required', 'numeric', 'between:-180,180'],
            'image' => ['nullable', 'image', 'max:4096'],
            'items' => ['nullable', 'array'],
            'items.*' => ['nullable', 'integer', 'min:0', 'max:999'],
        ]);

        // Contenu du pack : produits dont la quantité saisie est > 0 (un pack ne peut pas se contenir).
        $items = collect($data['items'] ?? [])
            ->filter(fn ($qty, $id) => (int) $qty > 0 && (int) $id !== $product?->id)
            ->mapWithKeys(fn ($qty, $id) => [(int) $id => ['quantity' => (int) $qty]])
            ->all();

        if ($data['type'] === 'pack' && $items === []) {
            throw ValidationException::withMessages(['items' => 'Un pack doit contenir au moins un produit (quantité > 0).']);
        }

        unset($data['image'], $data['items']);
        if (! empty($data['vendor_phone'])) {
            if (! Phone::isValid($data['vendor_phone'])) {
                throw ValidationException::withMessages(['vendor_phone' => 'Numéro du vendeur invalide.']);
            }
            $data['vendor_phone'] = Phone::normalize($data['vendor_phone']);
        }

        return [[...$data, 'is_active' => $request->boolean('is_active')], $items];
    }
}
