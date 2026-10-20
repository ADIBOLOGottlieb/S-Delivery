<?php

namespace Database\Seeders;

use App\Enums\Role;
use App\Models\User;
use App\Support\Identifier;
use App\Support\Phone;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

/**
 * Exécuté à chaque démarrage du conteneur (docker/entrypoint.sh) : chaque étape est rejouable sans risque.
 */
class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    /** Mot de passe admin par défaut : uniquement en environnement local explicite (APP_ENV=local). */
    private const LOCAL_ADMIN_PASSWORD = 'ChangeMoi2026!';

    public function run(): void
    {
        $this->seedAdmin();

        if (app()->environment('local')) {
            $this->seedDemoData();
        }
    }

    /**
     * Compte admin à partir de ADMIN_EMAIL / ADMIN_PASSWORD / ADMIN_PHONE.
     * - Créé s'il n'existe pas ; son mot de passe n'est plus réécrit à chaque démarrage
     *   (sauf ADMIN_PASSWORD_RESET=true, le temps d'un redéploiement).
     * - Un compte client ou livreur portant cet email n'est jamais promu admin.
     */
    private function seedAdmin(): void
    {
        $local = app()->environment('local');
        $email = Identifier::email(env('ADMIN_EMAIL') ?: ($local ? 'admin@sdelivery.tg' : null));
        $password = env('ADMIN_PASSWORD') ?: ($local ? self::LOCAL_ADMIN_PASSWORD : null);

        if ($email === null) {
            $this->command?->warn('ADMIN_EMAIL non défini : compte admin non créé.');

            return;
        }

        $existing = User::whereRaw('lower(email) = ?', [$email])->first();
        if ($existing) {
            if (! $existing->isAdmin()) {
                $this->command?->warn("Un compte non administrateur utilise déjà {$email} : il n'est pas promu admin.");

                return;
            }
            if (filter_var(env('ADMIN_PASSWORD_RESET', false), FILTER_VALIDATE_BOOL) && $password) {
                $existing->forceFill(['password' => $password, 'is_active' => true])->save();
                $this->command?->info('Mot de passe admin réinitialisé (pensez à retirer ADMIN_PASSWORD_RESET).');
            }

            return;
        }

        if (! $password) {
            $this->command?->warn('ADMIN_PASSWORD non défini : compte admin non créé.');

            return;
        }

        // Le numéro doit rester unique : s'il appartient déjà à un autre compte, l'admin reçoit un identifiant technique
        // (il se connecte au panneau par email, pas par téléphone).
        $phone = Phone::normalize((string) (env('ADMIN_PHONE') ?: '+22890000000'));
        if (User::whereIn('phone_number', Phone::variants($phone))->exists()) {
            $this->command?->warn("Le numéro {$phone} appartient déjà à un compte : l'admin est créé sans ce numéro.");
            $phone = 'admin-'.Str::lower(Str::random(10));
        }

        User::create([
            'name' => 'Administrateur S-Delivery',
            'email' => $email,
            'phone_number' => $phone,
            'password' => $password,
            'role' => Role::Admin,
            'is_active' => true,
        ]);
    }

    /** Comptes de démonstration (mots de passe connus) : jamais hors environnement local. */
    private function seedDemoData(): void
    {
        User::updateOrCreate(['phone_number' => '+22891000001'], [
            'name' => 'Kossi Livreur (démo)',
            'email' => 'livreur@sdelivery.tg',
            'password' => 'password123',
            'role' => Role::Courier,
            'vehicle' => 'Moto · TG-0001-AA',
            'is_active' => true,
        ]);

        User::updateOrCreate(['phone_number' => '+22892000001'], [
            'name' => 'Ama Cliente (démo)',
            'email' => 'client@sdelivery.tg',
            'password' => 'password123',
            'role' => Role::Client,
            'is_active' => true,
        ]);
    }
}
