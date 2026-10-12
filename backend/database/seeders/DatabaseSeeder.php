<?php

namespace Database\Seeders;

use App\Enums\Role;
use App\Models\User;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    public function run(): void
    {
        // Catalogue marketplace : créé une seule fois, y compris en production.
        $this->call(ProductCatalogSeeder::class);
        // Sous-catégories Agro + packs d'exemple : une seule fois.
        $this->call(CatalogStructureSeeder::class);
        // Courses alimentaires : Poissons et fruits de mer, Légumes, Céréales et conserves, Fruits, Viandes.
        $this->call(FoodCatalogSeeder::class);

        if (app()->isProduction() && ! env('ADMIN_PASSWORD')) {
            $this->command?->warn('ADMIN_PASSWORD non défini : compte admin non créé.');

            return;
        }

        User::updateOrCreate(['email' => env('ADMIN_EMAIL', 'admin@voom.tg')], [
            'name' => 'Administrateur VOOM',
            'phone_number' => env('ADMIN_PHONE', '+22890000000'),
            'password' => env('ADMIN_PASSWORD', 'ChangeMoi2026!'),
            'role' => Role::Admin,
            'is_active' => true,
        ]);

        if (! app()->isProduction()) {
            $this->seedDemoData();
        }
    }

    private function seedDemoData(): void
    {
        User::updateOrCreate(['phone_number' => '+22891000001'], [
            'name' => 'Kossi Livreur (démo)',
            'email' => 'livreur@voom.tg',
            'password' => 'password123',
            'role' => Role::Courier,
            'vehicle' => 'Moto · TG-0001-AA',
            'is_active' => true,
        ]);

        User::updateOrCreate(['phone_number' => '+22892000001'], [
            'name' => 'Ama Cliente (démo)',
            'email' => 'client@voom.tg',
            'password' => 'password123',
            'role' => Role::Client,
            'is_active' => true,
        ]);
    }
}
