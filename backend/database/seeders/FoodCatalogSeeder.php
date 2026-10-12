<?php

namespace Database\Seeders;

use App\Models\Product;
use App\Models\Setting;
use App\Models\Subcategory;
use Illuminate\Database\Seeder;

/**
 * « Courses alimentaires » (exécuté une seule fois, y compris en production) :
 * sous-onglets Poissons et fruits de mer, Légumes, Céréales et conserves, Fruits, Viandes
 * (+ Packs, affiché automatiquement en dernier dans l'app).
 * Les anciennes sous-catégories de départ sont fusionnées et leurs produits reclassés.
 */
class FoodCatalogSeeder extends Seeder
{
    /** Sous-catégorie => mots-clés, testés dans cet ordre (« conserve » avant « poisson » pour les sardines en boîte). */
    private const TARGETS = [
        'Céréales et conserves' => ['conserve', 'boîte', 'concentr'],
        'Poissons et fruits de mer' => ['poisson', 'crevette', 'crabe', 'fruits de mer', 'tilapia', 'carpe', 'calamar'],
        'Viandes' => ['viande', 'poulet', 'bœuf', 'boeuf', 'mouton', 'chèvre', 'porc', 'volaille', 'œuf', 'oeuf'],
        'Fruits' => ['fruit', 'ananas', 'banane', 'mangue', 'papaye', 'orange', 'avocat', 'coco'],
        'Légumes' => ['légume', 'tomate', 'oignon', 'piment', 'gombo', 'gboma', 'adémè', 'chou', 'carotte', 'laitue',
            'tubercule', 'igname', 'manioc', 'patate', 'pomme de terre'],
    ];

    /** Ordre des onglets demandé par l'agence. */
    private const ORDER = ['Poissons et fruits de mer', 'Légumes', 'Céréales et conserves', 'Fruits', 'Viandes'];

    /** Sous-catégories de la première version, remplacées par les nouvelles. */
    private const LEGACY = ['Céréales & légumineuses', 'Tubercules', 'Œufs, volaille & poisson', 'Huiles & transformés'];

    private const DEFAULT = 'Céréales et conserves';

    private const BE = ['Marché de Bè', 6.1365, 1.2470];

    private const ADAWLATO = ['Grand Marché de Lomé (Adawlato)', 6.1287, 1.2238];

    private const AGOE = ['Marché d\'Agoè-Assiyéyé', 6.2055, 1.2190];

    /** Nouveaux produits : nom, description, prix, unité, vendeur, lieu de retrait. */
    private const NEW_PRODUCTS = [
        ['Poisson frais (carpe)', 'Poisson · frais du jour', 2500, 'kg', 'Marché de Bè', self::BE],
        ['Tilapia frais', 'Poisson · frais du jour', 2000, 'kg', 'Marché de Bè', self::BE],
        ['Crevettes fraîches', 'Fruits de mer', 4500, 'kg', 'Marché de Bè', self::BE],
        ['Viande de bœuf', 'Viande · fraîche', 3500, 'kg', 'Boucherie Adawlato', self::ADAWLATO],
        ['Viande de mouton', 'Viande · fraîche', 4000, 'kg', 'Boucherie Adawlato', self::ADAWLATO],
        ['Poulet de chair découpé', 'Viande · volaille', 3000, 'kg', 'Ferme avicole Agoè', self::AGOE],
        ['Tomate concentrée (boîte 400 g)', 'Conserve', 600, 'boîte', 'Boutique Adawlato', self::ADAWLATO],
        ['Sardines à l\'huile (boîte)', 'Conserve', 500, 'boîte', 'Boutique Adawlato', self::ADAWLATO],
    ];

    public function run(): void
    {
        $this->retireShopping();

        if (Setting::get('food_catalog_v2')) {
            return;
        }

        // 1. Les 5 sous-catégories, dans l'ordre demandé.
        $subs = [];
        foreach (self::ORDER as $position => $name) {
            $sub = Subcategory::firstOrCreate(['category' => 'agro', 'name' => $name], ['position' => $position]);
            $sub->update(['position' => $position]);
            $subs[$name] = $sub;
        }

        // 2. Nouveaux produits (poissons, viandes, conserves).
        foreach (self::NEW_PRODUCTS as [$name, $description, $price, $unit, $vendor, [$address, $lat, $lng]]) {
            Product::firstOrCreate(['name' => $name], [
                'category' => 'agro', 'type' => 'product', 'description' => $description, 'price' => $price,
                'unit' => $unit, 'vendor_name' => $vendor, 'pickup_address' => $address,
                'pickup_lat' => $lat, 'pickup_lng' => $lng, 'is_active' => true,
            ]);
        }

        // 3. Reclasse les produits sans sous-catégorie ou rattachés à une ancienne.
        $legacyIds = Subcategory::where('category', 'agro')->whereIn('name', self::LEGACY)->pluck('id');
        Product::where('category', 'agro')->where('type', 'product')
            ->where(fn ($q) => $q->whereNull('subcategory_id')->orWhereIn('subcategory_id', $legacyIds))
            ->get()
            ->each(fn (Product $p) => $p->update(['subcategory_id' => $subs[$this->classify($p)]->id]));

        // 4. Les anciennes sous-catégories, désormais vides, disparaissent.
        Subcategory::whereIn('id', $legacyIds)->delete();

        Setting::put(['food_catalog_v2' => '1']);
    }

    /**
     * Shopping retiré de l'app et du panneau admin (une seule fois) : les produits sont masqués,
     * pas supprimés, car d'anciennes livraisons peuvent y faire référence.
     */
    private function retireShopping(): void
    {
        if (Setting::get('shopping_retired')) {
            return;
        }

        Product::where('category', 'shopping')->update(['is_active' => false]);
        Subcategory::where('category', 'shopping')->delete();

        Setting::put(['shopping_retired' => '1']);
    }

    private function classify(Product $product): string
    {
        $text = mb_strtolower($product->name.' '.$product->description);
        foreach (self::TARGETS as $name => $keywords) {
            foreach ($keywords as $keyword) {
                if (str_contains($text, $keyword)) {
                    return $name;
                }
            }
        }

        return self::DEFAULT;
    }
}
