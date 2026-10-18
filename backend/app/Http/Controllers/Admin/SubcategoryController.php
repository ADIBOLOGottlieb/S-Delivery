<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Product;
use App\Models\Subcategory;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\View\View;

/** Sous-catégories de la marketplace (onglets verticaux dans l'app). */
class SubcategoryController extends Controller
{
    public function index(): View
    {
        $groups = [];
        foreach (Product::CATEGORIES as $key => $label) {
            $groups[$key] = [
                'label' => $label,
                'items' => Subcategory::where('category', $key)->withCount('products')->orderBy('position')->orderBy('id')->get(),
            ];
        }

        return view('admin.subcategories.index', compact('groups'));
    }

    /** Renommage et ordre de toutes les sous-catégories d'une catégorie en une fois. */
    public function update(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'items' => ['required', 'array'],
            'items.*.name' => ['required', 'string', 'max:60'],
            'items.*.position' => ['required', 'integer', 'min:0', 'max:999'],
        ]);

        foreach ($data['items'] as $id => $values) {
            // Clé non numérique (formulaire trafiqué) : ignorée plutôt qu'une erreur SQL.
            if (! ctype_digit((string) $id)) {
                continue;
            }
            Subcategory::whereKey((int) $id)->update(['name' => $values['name'], 'position' => $values['position']]);
        }

        return back()->with('success', 'Sous-catégories enregistrées.');
    }

    public function store(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'category' => ['required', Rule::in(array_keys(Product::CATEGORIES))],
            'name' => ['required', 'string', 'max:60'],
        ]);

        Subcategory::create([...$data, 'position' => Subcategory::where('category', $data['category'])->max('position') + 1]);

        return back()->with('success', 'Sous-catégorie ajoutée.');
    }

    public function destroy(Subcategory $subcategory): RedirectResponse
    {
        // Les produits restent en vente, simplement sans sous-catégorie.
        $subcategory->delete();

        return back()->with('success', 'Sous-catégorie supprimée.');
    }
}
