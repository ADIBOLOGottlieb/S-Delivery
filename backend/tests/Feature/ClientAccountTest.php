<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\Phone;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ClientAccountTest extends TestCase
{
    use RefreshDatabase;

    /** Mot de passe affiché sur la page d'identifiants (une seule fois). */
    private function shownPassword(): string
    {
        $credentials = session('credentials');
        $this->assertNotEmpty($credentials);

        return $credentials[0]['password'];
    }

    public function test_phone_numbers_are_normalized(): void
    {
        $this->assertSame('+22890112233', Phone::normalize('90 11 22 33'));
        $this->assertSame('+22890112233', Phone::normalize('228-90-11-22-33'));
        $this->assertSame('+22890112233', Phone::normalize('00228 90112233'));
        $this->assertSame('+22890112233', Phone::normalize('+228 90 11 22 33'));
        $this->assertFalse(Phone::isValid('12345'));
    }

    public function test_admin_creates_old_client_who_logs_in_without_registering(): void
    {
        $admin = User::factory()->admin()->create();

        $this->actingAs($admin)->get('/admin/clients/create')->assertOk()->assertSee('Ajouter un ancien client');
        $this->post('/admin/clients', ['name' => 'Ama Mensah', 'phone_number' => '90 11 22 33', 'district' => 'Agoè'])
            ->assertRedirect(route('admin.clients.credentials'));
        $password = $this->shownPassword();
        $this->assertMatchesRegularExpression('/^\d{8}$/', $password);

        // Page des identifiants : mot de passe + lien WhatsApp pré-rempli.
        $this->get(route('admin.clients.credentials'))->assertOk()
            ->assertSee($password)->assertSee('wa.me/22890112233', false);

        $client = User::where('phone_number', '+22890112233')->firstOrFail();
        $this->assertSame('Agoè', $client->district);
        $this->app['auth']->forgetGuards();

        // Connexion directe, numéro tapé sous n'importe quelle forme.
        foreach (['90112233', '+228 90 11 22 33', '22890112233'] as $login) {
            $this->postJson('/api/v1/login', ['login' => $login, 'password' => $password])
                ->assertOk()
                ->assertJsonPath('user.name', 'Ama Mensah');
        }

        // Le même numéro ne peut pas se réinscrire : le client est renvoyé vers ses identifiants.
        $this->postJson('/api/v1/register', [
            'name' => 'Ama', 'phone_number' => '90-11-22-33', 'password' => 'secret123', 'password_confirmation' => 'secret123',
        ])->assertUnprocessable()->assertJsonValidationErrors('phone_number');
    }

    public function test_admin_imports_clients_from_excel_csv(): void
    {
        User::factory()->create(['phone_number' => '91000000']); // déjà inscrit (ancien format)
        $csv = "\xEF\xBB\xBFNom;Téléphone;Quartier\n"
            ."Ama Mensah;90 11 22 33;Agoè\n"
            ."Kossi Adjo;+228 92 22 33 44;Bè Kpota\n"
            ."Doublon Ama;22890112233;Agoè\n"
            ."Déjà inscrit;91 00 00 00;\n"
            ."Sans numéro;;Tokoin\n"
            ."Numéro court;1234;\n";
        $file = UploadedFile::fake()->createWithContent('clients.csv', $csv);

        $this->actingAs(User::factory()->admin()->create())
            ->post('/admin/clients/import', ['file' => $file])
            ->assertRedirect(route('admin.clients.credentials'));

        $created = session('credentials');
        $this->assertSame(['Ama Mensah', 'Kossi Adjo'], array_column($created, 'name'));
        $this->assertSame(['+22890112233', '+22892223344'], array_column($created, 'phone'));
        $this->assertCount(4, session('skipped'));
        $this->assertSame('Bè Kpota', User::where('phone_number', '+22892223344')->value('district'));

        $this->get(route('admin.clients.credentials'))->assertOk()->assertSee('Lignes ignorées (4)');
    }

    public function test_client_changes_credentials_in_the_app(): void
    {
        $client = User::factory()->create(['phone_number' => '+22890112233', 'password' => '12345678']);
        Sanctum::actingAs($client);

        $this->putJson('/api/v1/me/credentials', ['current_password' => 'mauvais', 'password' => 'nouveau123', 'password_confirmation' => 'nouveau123'])
            ->assertUnprocessable()->assertJsonValidationErrors('current_password');

        $this->putJson('/api/v1/me/credentials', [
            'current_password' => '12345678',
            'phone_number' => '93 44 55 66',
            'password' => 'nouveau123',
            'password_confirmation' => 'nouveau123',
        ])->assertOk()->assertJsonPath('data.phone_number', '+22893445566');
        $this->app['auth']->forgetGuards();

        $this->postJson('/api/v1/login', ['login' => '93445566', 'password' => 'nouveau123'])->assertOk();
        $this->postJson('/api/v1/login', ['login' => '90112233', 'password' => '12345678'])->assertUnprocessable();
    }

    public function test_admin_resets_a_forgotten_password(): void
    {
        $client = User::factory()->create(['phone_number' => '+22890112233', 'password' => 'ancien123']);
        $client->createToken('mobile');

        $this->actingAs(User::factory()->admin()->create())
            ->post(route('admin.clients.password', $client))
            ->assertRedirect(route('admin.clients.credentials'));
        $password = $this->shownPassword();
        $this->assertSame(0, $client->tokens()->count()); // anciennes sessions fermées
        $this->app['auth']->forgetGuards();

        $this->postJson('/api/v1/login', ['login' => '90112233', 'password' => $password])->assertOk();
        $this->postJson('/api/v1/login', ['login' => '90112233', 'password' => 'ancien123'])->assertUnprocessable();
    }

    public function test_clients_page_offers_add_and_import(): void
    {
        $this->actingAs(User::factory()->admin()->create())
            ->get('/admin/clients')->assertOk()
            ->assertSee('Ajouter un client')->assertSee('Importer (CSV)');
    }
}
