<?php

namespace Tests\Feature;

use App\Models\Delivery;
use App\Models\DeliveryRequest;
use App\Models\Media;
use App\Models\Payment;
use App\Models\Product;
use App\Models\Setting;
use App\Models\User;
use Database\Seeders\CatalogImageSeeder;
use Database\Seeders\CatalogStructureSeeder;
use Database\Seeders\FoodCatalogSeeder;
use Database\Seeders\ProductCatalogSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/** Mémoire (photos), recherches, identifiants, mot de passe oublié, suppression de compte, pages publiques. */
class HardeningTest extends TestCase
{
    use RefreshDatabase;

    private function payload(array $overrides = []): array
    {
        return [
            'type' => 'colis',
            'pickup_address' => 'Bè', 'pickup_lat' => 6.1375, 'pickup_lng' => 1.24,
            'dropoff_address' => 'Kégué', 'dropoff_lat' => 6.165, 'dropoff_lng' => 1.26,
            'recipient_name' => 'Yao', 'recipient_phone' => '+22893000000',
            ...$overrides,
        ];
    }

    private function makeDelivery(User $client, array $attributes = []): Delivery
    {
        return Delivery::forceCreate([...$this->payload(), 'client_id' => $client->id, 'distance_km' => 3,
            'delivery_fee' => 1000, 'items_amount' => 0, 'total_amount' => 1000, ...$attributes]);
    }

    private function deliveryWithPhoto(User $client): Delivery
    {
        Sanctum::actingAs($client);
        $id = $this->postJson('/api/v1/deliveries', $this->payload())->assertCreated()->json('data.id');
        $this->post("/api/v1/deliveries/{$id}/photos", ['photo' => UploadedFile::fake()->image('colis.jpg', 300, 200)],
            ['Accept' => 'application/json'])->assertOk();

        return Delivery::findOrFail($id);
    }

    // --- 1. La colonne data (base64) n'est jamais chargée dans les listes --------------

    public function test_delivery_lists_never_load_media_data(): void
    {
        $client = User::factory()->create();
        $delivery = $this->deliveryWithPhoto($client);

        DB::flushQueryLog();
        DB::enableQueryLog();
        $this->getJson('/api/v1/deliveries')->assertOk()->assertJsonCount(1, 'data.0.photos');
        $queries = collect(DB::getQueryLog())->pluck('query')->filter(fn ($q) => str_contains($q, '"media"'));
        DB::disableQueryLog();

        $this->assertNotEmpty($queries);
        foreach ($queries as $query) {
            $this->assertStringNotContainsString('"media".*', $query);
            $this->assertStringNotContainsString('"data"', $query);
        }

        // Relations chargées sans l'attribut data, et l'image reste servie en entier.
        $photo = Delivery::with('photos')->findOrFail($delivery->id)->photos->first();
        $this->assertArrayNotHasKey('data', $photo->getAttributes());
        $this->assertNotEmpty($photo->uuid);
        $this->assertNotSame('', $photo->bytes());
        $this->get($photo->url())->assertOk()->assertHeader('Content-Type', 'image/jpeg');
        $this->assertArrayNotHasKey('data', Media::firstOrFail()->getAttributes());
    }

    public function test_large_photos_are_resized_to_1600_px(): void
    {
        $media = Media::fromUpload(UploadedFile::fake()->image('grande.png', 3200, 2000));
        [$width, $height] = getimagesizefromstring($media->bytes());

        $this->assertSame([1600, 1000], [$width, $height]);
        $this->assertSame('image/jpeg', $media->mime);
        $this->assertSame(strlen($media->bytes()), $media->size);

        // Petite image : gardée telle quelle.
        $small = UploadedFile::fake()->image('petite.png', 200, 100);
        $kept = Media::fromUpload($small);
        $this->assertSame('image/png', $kept->mime);
        $this->assertSame($small->getContent(), $kept->bytes());
    }

    // --- 11. Captures de paiement jamais servies publiquement ---------------------------

    public function test_payment_screenshot_is_not_served_by_public_media_route(): void
    {
        $client = User::factory()->create();
        Sanctum::actingAs($client);
        $id = $this->postJson('/api/v1/deliveries', $this->payload())->json('data.id');
        $response = $this->post("/api/v1/deliveries/{$id}/payment", [
            'method' => 'flooz', 'transaction_ref' => 'FLZ9', 'payer_phone' => '+22899000000',
            'screenshot' => UploadedFile::fake()->image('capture.jpg'),
        ], ['Accept' => 'application/json'])->assertOk();

        $payment = Payment::firstOrFail();
        $uuid = $payment->screenshot->uuid;
        $this->assertStringNotContainsString($uuid, $response->getContent());
        $this->get("/media/{$uuid}")->assertNotFound();

        $this->app['auth']->forgetGuards();
        $this->actingAs(User::factory()->admin()->create())
            ->get(route('admin.payments.screenshot', $payment))->assertOk();
    }

    // --- 6. Recherches insensibles à la casse, emails en minuscules ---------------------

    public function test_searches_are_case_insensitive(): void
    {
        $admin = User::factory()->admin()->create();
        $client = User::factory()->create(['name' => 'Afi Mensah', 'email' => 'afi@example.com']);
        $delivery = $this->deliveryWithPhoto($client);
        Product::create([
            'category' => 'agro', 'type' => 'product', 'name' => 'Tomate fraîche', 'price' => 500,
            'pickup_address' => 'Marché', 'pickup_lat' => 6.13, 'pickup_lng' => 1.22, 'is_active' => true,
        ]);

        $this->getJson('/api/v1/products?search=TOMATE')->assertOk()->assertJsonPath('data.0.name', 'Tomate fraîche');
        $this->getJson('/api/v1/products?search=50%25')->assertOk()->assertJsonCount(0, 'data');

        $this->app['auth']->forgetGuards();
        $this->actingAs($admin);
        $this->get(route('admin.clients.index', ['search' => 'AFI MEN']))->assertOk()->assertSee('Afi Mensah');
        $this->get(route('admin.clients.index', ['search' => 'AFI@EXAMPLE']))->assertOk()->assertSee('Afi Mensah');
        $this->get(route('admin.deliveries.index', ['search' => strtolower($delivery->reference)]))
            ->assertOk()->assertSee($delivery->reference);
        $this->get(route('admin.deliveries.index', ['search' => 'afi mensah']))->assertOk()->assertSee($delivery->reference);
    }

    public function test_emails_are_stored_lowercase_and_matched_without_case(): void
    {
        $this->postJson('/api/v1/register', [
            'name' => 'Kodjo', 'email' => '  Kodjo@Example.COM ', 'phone_number' => '90 55 66 77',
            'password' => 'secret-123', 'password_confirmation' => 'secret-123',
        ])->assertCreated()->assertJsonPath('user.email', 'kodjo@example.com');

        // Même email écrit autrement : refusé à l'inscription, accepté à la connexion.
        $this->postJson('/api/v1/register', [
            'name' => 'Autre', 'email' => 'KODJO@example.com', 'phone_number' => '90 55 66 78',
            'password' => 'secret-123', 'password_confirmation' => 'secret-123',
        ])->assertUnprocessable()->assertJsonValidationErrors('email');
        $this->postJson('/api/v1/login', ['login' => 'KoDjO@example.com', 'password' => 'secret-123'])->assertOk();

        // Ancien compte enregistré avec des majuscules : retrouvé quand même.
        User::factory()->create(['email' => 'Ama.Old@Example.com', 'phone_number' => '+22890112244']);
        $this->postJson('/api/v1/login', ['login' => 'ama.old@example.com', 'password' => 'password'])->assertOk();

        $user = User::where('email', 'kodjo@example.com')->firstOrFail();
        Sanctum::actingAs($user);
        $this->putJson('/api/v1/me/credentials', ['current_password' => 'secret-123', 'email' => 'Nouveau@Example.com'])
            ->assertOk()->assertJsonPath('data.email', 'nouveau@example.com');
        $this->putJson('/api/v1/me/credentials', ['current_password' => 'secret-123', 'email' => 'AMA.OLD@example.com'])
            ->assertUnprocessable()->assertJsonValidationErrors('email');

        $this->app['auth']->forgetGuards();
        $admin = User::factory()->admin()->create(['email' => 'Chef@Voom.tg']);
        $this->post('/admin/login', ['email' => 'chef@voom.tg', 'password' => 'password'])->assertRedirect(route('admin.dashboard'));
        $this->assertAuthenticatedAs($admin);
    }

    // --- 7. Identifiants non numériques : 404 / 422, jamais d'erreur SQL ---------------

    public function test_non_numeric_identifiers_are_rejected_cleanly(): void
    {
        $client = User::factory()->create();
        Sanctum::actingAs($client);
        $this->getJson('/api/v1/deliveries/abc')->assertNotFound();
        $this->getJson('/api/v1/requests/1%20or%201=1')->assertNotFound();
        $this->postJson('/api/v1/deliveries', $this->payload(['product_id' => 'abc', 'quantity' => 1]))
            ->assertUnprocessable()->assertJsonPath('errors.product_id.0', "Ce produit n'est plus disponible.");

        $this->app['auth']->forgetGuards();
        $admin = User::factory()->admin()->create();
        $delivery = $this->makeDelivery($client);
        $this->actingAs($admin)->get('/admin/deliveries/abc')->assertNotFound();
        $this->get('/admin/products/x/edit')->assertNotFound();
        $this->post(route('admin.deliveries.assign', $delivery), ['courier_id' => 'abc'])->assertSessionHasErrors('courier_id');
    }

    // --- 9. Mot de passe oublié sans énumération ----------------------------------------

    public function test_forgot_password_gives_the_same_answer_whether_the_account_exists_or_not(): void
    {
        User::factory()->create(['email' => 'ama@example.com', 'phone_number' => '+22890112233']);
        User::factory()->create(['email' => 'off@example.com', 'is_active' => false]);
        User::factory()->admin()->create(['email' => 'boss@example.com']);

        $existing = $this->postJson('/api/v1/password/forgot', ['login' => 'AMA@example.com'])->assertOk()->json();
        $unknown = $this->postJson('/api/v1/password/forgot', ['login' => 'personne@example.com'])->assertOk()->json();
        $inactive = $this->postJson('/api/v1/password/forgot', ['login' => 'off@example.com'])->assertOk()->json();
        $adminAnswer = $this->postJson('/api/v1/password/forgot', ['login' => 'boss@example.com'])->assertOk()->json();

        $this->assertSame(array_keys($existing), array_keys($unknown));
        $this->assertSame($existing['message'], $unknown['message']);
        $this->assertSame($existing['message'], $inactive['message']);
        $this->assertSame($existing['message'], $adminAnswer['message']);
        $this->assertSame('p*******@example.com', $unknown['email']);

        // Un seul email réellement envoyé (au compte actif), aucun code pour les autres.
        $this->assertCount(1, app('mailer')->getSymfonyTransport()->messages());
        $this->assertDatabaseCount('password_reset_tokens', 1);
    }

    public function test_reset_is_refused_for_inactive_and_admin_accounts(): void
    {
        $user = User::factory()->create(['email' => 'ama@example.com']);
        $this->postJson('/api/v1/password/forgot', ['login' => 'ama@example.com'])->assertOk();
        preg_match('/(\d{6})/', collect(app('mailer')->getSymfonyTransport()->messages())->last()->getOriginalMessage()->getTextBody(), $m);

        $user->update(['is_active' => false]);
        $this->postJson('/api/v1/password/reset', [
            'login' => 'ama@example.com', 'code' => $m[1], 'password' => 'nouveau-mdp', 'password_confirmation' => 'nouveau-mdp',
        ])->assertUnprocessable()->assertJsonValidationErrors('code');

        $admin = User::factory()->admin()->create(['email' => 'boss@example.com']);
        DB::table('password_reset_tokens')->insert(['email' => $admin->email, 'token' => bcrypt('123456'), 'created_at' => now()]);
        $this->postJson('/api/v1/password/reset', [
            'login' => 'boss@example.com', 'code' => '123456', 'password' => 'nouveau-mdp', 'password_confirmation' => 'nouveau-mdp',
        ])->assertUnprocessable();
        $this->assertTrue(\Hash::check('password', $admin->fresh()->password));
    }

    // --- 5. Limites par identifiant visé (pas seulement par IP) -----------------------

    public function test_forgot_password_is_limited_per_account_even_from_different_ips(): void
    {
        User::factory()->create(['email' => 'ama@example.com']);

        foreach (['10.0.0.1', '10.0.0.2', '10.0.0.3'] as $ip) {
            $this->withServerVariables(['REMOTE_ADDR' => $ip])
                ->postJson('/api/v1/password/forgot', ['login' => 'ama@example.com'])->assertOk();
        }
        $this->withServerVariables(['REMOTE_ADDR' => '10.0.0.4'])
            ->postJson('/api/v1/password/forgot', ['login' => 'AMA@example.com'])
            ->assertStatus(429)->assertJsonPath('message', fn ($m) => str_starts_with($m, 'Trop de tentatives.'));
    }

    // --- 13. Suppression de compte -----------------------------------------------------

    public function test_client_deletes_account_which_is_anonymized_and_history_kept(): void
    {
        $client = User::factory()->create(['name' => 'Ama', 'email' => 'ama@example.com', 'phone_number' => '+22890112233']);
        $delivery = $this->deliveryWithPhoto($client);
        $this->post('/api/v1/me/avatar', ['photo' => UploadedFile::fake()->image('moi.jpg')], ['Accept' => 'application/json'])->assertOk();
        $client->refresh()->forceFill(['fcm_token' => 'jeton-appareil'])->save();
        $client->createToken('autre-appareil');
        $avatarId = $client->avatar_media_id;

        $this->deleteJson('/api/v1/me', ['password' => 'mauvais'])->assertUnprocessable()->assertJsonValidationErrors('password');
        $this->deleteJson('/api/v1/me', ['password' => 'password'])->assertOk();

        $client->refresh();
        $this->assertSame('Compte supprimé', $client->name);
        $this->assertFalse($client->is_active);
        $this->assertNotNull($client->anonymized_at);
        $this->assertStringStartsWith('supprime-', $client->phone_number);
        $this->assertStringEndsWith('.invalid', $client->email);
        $this->assertNull($client->fcm_token);
        $this->assertNull($client->avatar_media_id);
        $this->assertNull(Media::find($avatarId));
        $this->assertSame(0, $client->tokens()->count());

        // Historique conservé ; livraison jamais payée annulée.
        $this->assertSame('cancelled', $delivery->fresh()->status->value);
        $this->assertSame($client->id, $delivery->fresh()->client_id);

        // Plus personne ne peut se connecter ; le numéro peut resservir pour un nouveau compte.
        $this->app['auth']->forgetGuards();
        $this->postJson('/api/v1/login', ['login' => '90112233', 'password' => 'password'])->assertUnprocessable();
        $this->postJson('/api/v1/register', [
            'name' => 'Ama', 'phone_number' => '90112233', 'email' => 'ama@example.com',
            'password' => 'secret-123', 'password_confirmation' => 'secret-123',
        ])->assertCreated();

        // L'admin ne peut pas réactiver un compte supprimé.
        $this->actingAs(User::factory()->admin()->create())
            ->post(route('admin.clients.toggle', $client))->assertSessionHasErrors('client');
        $this->assertFalse($client->fresh()->is_active);
    }

    public function test_account_deletion_is_refused_with_an_active_delivery_or_for_admins(): void
    {
        $client = User::factory()->create();
        $delivery = $this->deliveryWithPhoto($client);
        $delivery->forceFill(['payment_status' => 'verified'])->save();

        $this->deleteJson('/api/v1/me', ['password' => 'password'])
            ->assertUnprocessable()
            ->assertJsonPath('errors.account.0', fn ($m) => str_contains($m, 'livraison est en cours'));
        $this->assertTrue($client->fresh()->is_active);

        $delivery->forceFill(['status' => 'delivered'])->save();
        $this->deleteJson('/api/v1/me', ['password' => 'password'])->assertOk();

        $this->app['auth']->forgetGuards();
        $courier = User::factory()->courier()->create();
        $this->makeDelivery(User::factory()->create(), ['courier_id' => $courier->id, 'status' => 'picked_up', 'payment_status' => 'verified']);
        Sanctum::actingAs($courier);
        $this->deleteJson('/api/v1/me', ['password' => 'password'])->assertUnprocessable();

        $this->app['auth']->forgetGuards();
        $admin = User::factory()->admin()->create();
        Sanctum::actingAs($admin);
        $this->deleteJson('/api/v1/me', ['password' => 'password'])->assertForbidden();
        $this->assertTrue($admin->fresh()->is_active);
    }

    // --- 14. Pages publiques et liens dans /payment-info ---------------------------------

    public function test_privacy_and_account_deletion_pages_are_public(): void
    {
        Setting::put(['support_phone' => '+22891234567', 'support_email' => 'contact@voom.tg']);

        $this->get('/confidentialite')->assertOk()
            ->assertSee('Politique de confidentialité')
            ->assertSee('Render')
            ->assertSee('+22891234567')
            ->assertSee('contact@voom.tg')
            ->assertSee(route('legal.account-deletion'));
        $this->get('/compte/suppression')->assertOk()
            ->assertSee('Profil › Supprimer mon compte')
            ->assertSee('+22891234567');

        Sanctum::actingAs(User::factory()->create());
        $this->getJson('/api/v1/payment-info')->assertOk()
            ->assertJsonPath('privacy_url', url('/confidentialite'))
            ->assertJsonPath('account_deletion_url', url('/compte/suppression'))
            ->assertJsonPath('support_email', 'contact@voom.tg');
        $this->assertStringStartsWith('http', $this->getJson('/api/v1/payment-info')->json('privacy_url'));
    }

    // --- 8. Photos du catalogue posées une seule fois --------------------------------

    public function test_catalog_images_are_seeded_once_and_removed_photos_stay_removed(): void
    {
        $this->seed(ProductCatalogSeeder::class);
        $this->seed(CatalogStructureSeeder::class);
        $this->seed(FoodCatalogSeeder::class);
        $this->seed(CatalogImageSeeder::class);
        $this->assertSame('catalog/mangue.jpg', Product::where('name', 'Mangue')->value('image_path'));

        // L'admin retire la photo : le redéploiement suivant ne la remet pas.
        Product::where('name', 'Mangue')->update(['image_path' => null]);
        $this->seed(CatalogImageSeeder::class);
        $this->assertNull(Product::where('name', 'Mangue')->value('image_path'));
    }

    public function test_admin_seeding_never_promotes_a_client_nor_resets_the_password(): void
    {
        $client = User::factory()->create(['email' => 'admin@voom.tg']);
        $backup = [$_SERVER, $_ENV];
        foreach (['ADMIN_EMAIL' => 'Admin@Voom.tg', 'ADMIN_PASSWORD' => 'Secret-Admin-1', 'ADMIN_PHONE' => '+22890000000'] as $k => $v) {
            $_SERVER[$k] = $_ENV[$k] = $v;
        }
        unset($_SERVER['ADMIN_PASSWORD_RESET'], $_ENV['ADMIN_PASSWORD_RESET']);
        try {
            $this->seed();
            $this->assertSame('client', $client->fresh()->role->value);
            $this->assertSame(0, User::where('role', 'admin')->count());

            $client->update(['email' => 'autre@example.com']);
            $this->seed();
            $admin = User::where('role', 'admin')->firstOrFail();
            $this->assertSame('admin@voom.tg', $admin->email);
            $this->assertTrue(\Hash::check('Secret-Admin-1', $admin->password));

            // Mot de passe changé depuis : un redémarrage ne le réécrit pas.
            $admin->update(['password' => 'Choisi-Par-Admin']);
            $this->seed();
            $this->assertTrue(\Hash::check('Choisi-Par-Admin', $admin->fresh()->password));
        } finally {
            [$_SERVER, $_ENV] = $backup;
        }
    }
}
