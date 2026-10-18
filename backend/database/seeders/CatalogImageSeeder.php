<?php

namespace Database\Seeders;

use App\Models\Product;
use App\Models\Setting;
use Illuminate\Database\Seeder;

/**
 * Photos réalistes du catalogue Courses alimentaires (CC0 / domaine public, voir
 * public/images/catalog/CREDITS.md), livrées avec l'application : elles survivent aux redéploiements.
 * Exécuté une seule fois (réglage « catalog_images_seeded ») : une photo envoyée par l'admin n'est jamais
 * remplacée, et une photo retirée par l'admin ne revient pas au redéploiement suivant.
 */
class CatalogImageSeeder extends Seeder
{
    /** Nom du produit => fichier dans public/images/catalog/. */
    public const IMAGES = [
        'Maïs jaune (grain)' => 'mais-jaune',
        'Maïs blanc (grain)' => 'mais-blanc',
        'Riz local étuvé' => 'riz-etuve',
        'Riz parfumé (sac 25 kg)' => 'riz-sac',
        'Mil' => 'mil',
        'Sorgho' => 'sorgho',
        'Fonio' => 'fonio',
        'Haricot blanc (niébé)' => 'niebe',
        'Haricot rouge' => 'haricot-rouge',
        'Soja' => 'soja',
        'Arachide décortiquée' => 'arachide',
        'Gari' => 'gari',
        'Farine de maïs' => 'farine-mais',
        'Tomate fraîche' => 'tomate',
        'Oignon' => 'oignon',
        'Piment frais' => 'piment',
        'Gombo frais' => 'gombo',
        'Aubergine locale (gboma)' => 'gboma',
        "Feuilles d'adémè" => 'ademe',
        'Feuilles de gboma' => 'feuilles-gboma',
        'Chou' => 'chou',
        'Carotte' => 'carotte',
        'Laitue' => 'laitue',
        'Igname' => 'igname',
        'Manioc frais' => 'manioc',
        'Patate douce' => 'patate-douce',
        'Pomme de terre' => 'pomme-de-terre',
        'Ananas pain de sucre' => 'ananas',
        'Banane plantain' => 'plantain',
        'Mangue' => 'mangue',
        'Papaye' => 'papaye',
        'Orange' => 'orange',
        'Avocat' => 'avocat',
        'Noix de coco' => 'coco',
        'Huile de palme' => 'huile-palme',
        "Huile d'arachide" => 'huile-arachide',
        'Œufs (plateau de 30)' => 'oeufs',
        'Poulet bicyclette' => 'poulet-bicyclette',
        'Poisson fumé' => 'poisson-fume',
        'Miel local' => 'miel',
        'Poisson frais (carpe)' => 'carpe',
        'Tilapia frais' => 'tilapia',
        'Crevettes fraîches' => 'crevettes',
        'Viande de bœuf' => 'boeuf',
        'Viande de mouton' => 'mouton',
        'Poulet de chair découpé' => 'poulet-decoupe',
        'Tomate concentrée (boîte 400 g)' => 'tomate-concentree',
        "Sardines à l'huile (boîte)" => 'sardines',
        'Pack sauce légumes' => 'pack-sauce',
        'Pack céréales familial' => 'pack-cereales',
    ];

    public const FLAG = 'catalog_images_seeded';

    public function run(): void
    {
        if (Setting::get(self::FLAG)) {
            return;
        }

        // Base où une version précédente (sans réglage) a déjà posé les photos : on ne repasse pas,
        // pour ne pas remettre une photo retirée entre-temps par l'admin.
        if (! Product::where('image_path', 'like', 'catalog/%')->exists()) {
            foreach (self::IMAGES as $name => $file) {
                if (! is_file(public_path("images/catalog/$file.jpg"))) {
                    continue;
                }

                // Uniquement les produits sans photo : rien n'est jamais remplacé.
                Product::where('name', $name)->whereNull('image_path')
                    ->update(['image_path' => "catalog/$file.jpg"]);
            }
        }

        Setting::put([self::FLAG => '1']);
    }
}
