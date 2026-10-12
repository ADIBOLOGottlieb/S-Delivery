<?php

namespace Database\Seeders;

use App\Models\Product;
use App\Models\Setting;
use Illuminate\Database\Seeder;

/**
 * Catalogue de départ de la marketplace (Shopping + Agroalimentaire).
 *
 * Exécuté une seule fois (réglage « catalog_seeded ») : ensuite l'admin gère les produits
 * librement, sans qu'un redéploiement ne recrée ou n'écrase quoi que ce soit.
 * Prix indicatifs en FCFA et points de retrait approximatifs, à ajuster dans le panneau admin.
 */
class ProductCatalogSeeder extends Seeder
{
    /** [nom, coordonnées] des points de retrait. */
    private const MARKETS = [
        'grand_marche' => ['Grand Marché de Lomé (Adawlato)', 6.1287, 1.2238],
        'hedzranawoe' => ['Marché de Hédzranawoé', 6.1595, 1.2425],
        'agoe' => ['Marché d\'Agoè-Assiyéyé', 6.2055, 1.2190],
        'be' => ['Marché de Bè', 6.1365, 1.2470],
        'deckon' => ['Déckon, Boulevard du 13 Janvier', 6.1335, 1.2195],
    ];

    public function run(bool $force = false): void
    {
        if (! $force && Setting::get('catalog_seeded')) {
            return;
        }

        foreach ($this->products() as [$category, $name, $description, $price, $unit, $vendor, $market]) {
            [$address, $lat, $lng] = self::MARKETS[$market];

            Product::firstOrCreate(['name' => $name], [
                'category' => $category,
                'description' => $description,
                'price' => $price,
                'unit' => $unit,
                'vendor_name' => $vendor,
                'pickup_address' => $address,
                'pickup_lat' => $lat,
                'pickup_lng' => $lng,
                'is_active' => true,
            ]);
        }

        Setting::put(['catalog_seeded' => '1']);
    }

    /** @return list<array{0: string, 1: string, 2: string, 3: int, 4: string, 5: string, 6: string}> */
    private function products(): array
    {
        return [
            // --- Agro : céréales et légumineuses ---
            ['agro', 'Maïs jaune (grain)', 'Céréale · maïs sec local', 400, 'kg', 'Coopérative Agoè', 'agoe'],
            ['agro', 'Maïs blanc (grain)', 'Céréale · maïs sec local', 400, 'kg', 'Coopérative Agoè', 'agoe'],
            ['agro', 'Riz local étuvé', 'Céréale · riz togolais', 700, 'kg', 'Coopérative Agoè', 'agoe'],
            ['agro', 'Riz parfumé (sac 25 kg)', 'Céréale · riz long grain', 17500, 'sac', 'Boutique Adawlato', 'grand_marche'],
            ['agro', 'Mil', 'Céréale · grain sec', 600, 'kg', 'Coopérative Agoè', 'agoe'],
            ['agro', 'Sorgho', 'Céréale · grain sec', 550, 'kg', 'Coopérative Agoè', 'agoe'],
            ['agro', 'Fonio', 'Céréale · décortiqué', 1500, 'kg', 'Coopérative Agoè', 'agoe'],
            ['agro', 'Haricot blanc (niébé)', 'Légumineuse · sec', 900, 'kg', 'Coopérative Agoè', 'agoe'],
            ['agro', 'Haricot rouge', 'Légumineuse · sec', 1000, 'kg', 'Coopérative Agoè', 'agoe'],
            ['agro', 'Soja', 'Légumineuse · grain', 500, 'kg', 'Coopérative Agoè', 'agoe'],
            ['agro', 'Arachide décortiquée', 'Légumineuse · grain', 1200, 'kg', 'Coopérative Agoè', 'agoe'],
            ['agro', 'Gari', 'Semoule de manioc', 600, 'kg', 'Coopérative Agoè', 'agoe'],
            ['agro', 'Farine de maïs', 'Farine · pour pâte / akoumé', 500, 'kg', 'Boutique Adawlato', 'grand_marche'],

            // --- Agro : légumes ---
            ['agro', 'Tomate fraîche', 'Légume · tomate locale', 800, 'kg', 'Étal Hédzranawoé', 'hedzranawoe'],
            ['agro', 'Oignon', 'Légume · oignon violet', 700, 'kg', 'Étal Hédzranawoé', 'hedzranawoe'],
            ['agro', 'Piment frais', 'Légume · piment local', 1500, 'kg', 'Étal Hédzranawoé', 'hedzranawoe'],
            ['agro', 'Gombo frais', 'Légume · gombo', 1000, 'kg', 'Étal Hédzranawoé', 'hedzranawoe'],
            ['agro', 'Aubergine locale (gboma)', 'Légume', 800, 'kg', 'Étal Hédzranawoé', 'hedzranawoe'],
            ['agro', 'Feuilles d\'adémè', 'Légume feuille (corète)', 300, 'botte', 'Étal Hédzranawoé', 'hedzranawoe'],
            ['agro', 'Feuilles de gboma', 'Légume feuille (épinard africain)', 300, 'botte', 'Étal Hédzranawoé', 'hedzranawoe'],
            ['agro', 'Chou', 'Légume · chou pommé', 500, 'pièce', 'Étal Hédzranawoé', 'hedzranawoe'],
            ['agro', 'Carotte', 'Légume', 900, 'kg', 'Étal Hédzranawoé', 'hedzranawoe'],
            ['agro', 'Laitue', 'Légume feuille', 250, 'pièce', 'Étal Hédzranawoé', 'hedzranawoe'],

            // --- Agro : tubercules ---
            ['agro', 'Igname', 'Tubercule', 700, 'kg', 'Marché de Bè', 'be'],
            ['agro', 'Manioc frais', 'Tubercule', 300, 'kg', 'Marché de Bè', 'be'],
            ['agro', 'Patate douce', 'Tubercule', 500, 'kg', 'Marché de Bè', 'be'],
            ['agro', 'Pomme de terre', 'Tubercule', 1000, 'kg', 'Marché de Bè', 'be'],

            // --- Agro : fruits ---
            ['agro', 'Ananas pain de sucre', 'Fruit', 500, 'pièce', 'Marché de Bè', 'be'],
            ['agro', 'Banane plantain', 'Fruit · régime moyen', 2500, 'régime', 'Marché de Bè', 'be'],
            ['agro', 'Mangue', 'Fruit de saison', 150, 'pièce', 'Marché de Bè', 'be'],
            ['agro', 'Papaye', 'Fruit', 600, 'pièce', 'Marché de Bè', 'be'],
            ['agro', 'Orange', 'Fruit', 1000, 'lot de 10', 'Marché de Bè', 'be'],
            ['agro', 'Avocat', 'Fruit', 200, 'pièce', 'Marché de Bè', 'be'],
            ['agro', 'Noix de coco', 'Fruit', 300, 'pièce', 'Marché de Bè', 'be'],

            // --- Agro : produits transformés et frais ---
            ['agro', 'Huile de palme', 'Huile rouge locale', 1500, 'litre', 'Boutique Adawlato', 'grand_marche'],
            ['agro', 'Huile d\'arachide', 'Huile végétale', 1800, 'litre', 'Boutique Adawlato', 'grand_marche'],
            ['agro', 'Œufs (plateau de 30)', 'Œufs frais', 2700, 'plateau', 'Ferme avicole Agoè', 'agoe'],
            ['agro', 'Poulet bicyclette', 'Poulet local vivant', 4500, 'pièce', 'Ferme avicole Agoè', 'agoe'],
            ['agro', 'Poisson fumé', 'Poisson · fumé artisanal', 2000, 'lot', 'Marché de Bè', 'be'],
            ['agro', 'Miel local', 'Miel naturel', 3000, 'pot 500 g', 'Coopérative Agoè', 'agoe'],
        ];
    }
}
