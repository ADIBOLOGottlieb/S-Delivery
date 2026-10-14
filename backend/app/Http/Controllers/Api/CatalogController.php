<?php

namespace App\Http\Controllers\Api;

use App\Enums\PaymentMethod;
use App\Http\Controllers\Controller;
use App\Http\Resources\ProductResource;
use App\Http\Resources\PromotionResource;
use App\Models\Product;
use App\Models\Promotion;
use App\Models\Setting;
use App\Models\Subcategory;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;

class CatalogController extends Controller
{
    /** Produits et packs de la marketplace (gérés par l'admin). */
    public function products(Request $request): AnonymousResourceCollection
    {
        $data = $request->validate([
            'category' => ['nullable', Rule::in(array_keys(Product::CATEGORIES))],
            'subcategory_id' => ['nullable', 'integer'],
            // « Autres produits » : produits sans famille (sous-catégorie).
            'others' => ['nullable', 'boolean'],
            'type' => ['nullable', Rule::in(['product', 'pack'])],
            'search' => ['nullable', 'string', 'max:100'],
        ]);

        $products = Product::query()
            ->with('packItems')
            ->where('is_active', true)
            ->when($data['category'] ?? null, fn ($q, $c) => $q->where('category', $c))
            ->when($data['subcategory_id'] ?? null, fn ($q, $s) => $q->where('subcategory_id', $s))
            ->when($request->boolean('others'), fn ($q) => $q->whereNull('subcategory_id')->where('type', 'product'))
            ->when($data['type'] ?? null, fn ($q, $t) => $q->where('type', $t))
            ->when($data['search'] ?? null, fn ($q, $s) => $q->where('name', 'like', "%{$s}%"))
            ->orderByRaw("case when type = 'pack' then 0 else 1 end")
            ->orderBy('name')
            ->paginate(100);

        return ProductResource::collection($products);
    }

    /** Sous-catégories (onglets verticaux) d'une catégorie, dans l'ordre choisi par l'admin. */
    public function subcategories(Request $request): JsonResponse
    {
        $category = $request->validate(['category' => ['required', Rule::in(array_keys(Product::CATEGORIES))]])['category'];

        return response()->json([
            'data' => Subcategory::where('category', $category)->orderBy('position')->orderBy('id')->get(['id', 'name']),
            'has_packs' => Product::where('category', $category)->where('type', 'pack')->where('is_active', true)->exists(),
            'has_others' => Product::where('category', $category)->where('type', 'product')->where('is_active', true)
                ->whereNull('subcategory_id')->exists(),
        ]);
    }

    /** Annonces promo visibles (bandeau défilant de l'accueil). */
    public function promotions(): AnonymousResourceCollection
    {
        return PromotionResource::collection(Promotion::visible()->with('product.packItems')->latest()->limit(10)->get());
    }

    /** Numéros marchands Flooz / Mixx by Yas : le client vire puis envoie la capture d'écran. */
    public function paymentInfo(): JsonResponse
    {
        $methods = [];
        foreach (PaymentMethod::cases() as $method) {
            $number = Setting::get("{$method->value}_merchant_number");
            if ($number) {
                $methods[] = ['method' => $method->value, 'label' => $method->label(), 'merchant_number' => $number];
            }
        }

        return response()->json([
            'merchant_name' => Setting::get('merchant_name'),
            'instructions' => Setting::get('payment_instructions'),
            'support_phone' => Setting::get('support_phone') ?: null,
            'methods' => $methods,
        ]);
    }
}
