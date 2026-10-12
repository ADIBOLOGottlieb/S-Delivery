<?php

namespace Tests\Feature;

use App\Models\Delivery;
use App\Models\Product;
use App\Models\Promotion;
use App\Models\Subcategory;
use App\Models\User;
use Database\Seeders\CatalogStructureSeeder;
use Database\Seeders\FoodCatalogSeeder;
use Database\Seeders\ProductCatalogSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request as HttpRequest;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CatalogPromoReminderTest extends TestCase
{
    use RefreshDatabase;

    /** Compte de service Firebase factice + réponses Google simulées (jeton OAuth déjà en cache). */
    private function fakeFirebase(): void
    {
        config(['services.fcm.credentials' => base64_encode(json_encode([
            'project_id' => 'voom-test', 'client_email' => 'push@voom-test.iam.gserviceaccount.com', 'private_key' => 'unused',
        ]))]);
        Cache::put('fcm_access_token', 'tok', 3600);

        Http::fake([
            'oauth2.googleapis.com/token' => Http::response(['access_token' => 'tok', 'expires_in' => 3600]),
            'fcm.googleapis.com/*' => Http::response(['name' => 'projects/voom-test/messages/1']),
        ]);
    }

    private function delivery(User $client, array $overrides = []): Delivery
    {
        Sanctum::actingAs($client);
        $id = $this->postJson('/api/v1/deliveries', [
            'type' => 'colis',
            'pickup_address' => 'Bè', 'pickup_lat' => 6.1375, 'pickup_lng' => 1.24,
            'dropoff_address' => 'Kégué', 'dropoff_lat' => 6.165, 'dropoff_lng' => 1.26,
            'recipient_name' => 'Yao', 'recipient_phone' => '+22893000000',
            ...$overrides,
        ])->assertCreated()->json('data.id');
        $this->app['auth']->forgetGuards();

        return Delivery::findOrFail($id);
    }

    public function test_agro_has_six_subcategories_and_packs(): void
    {
        $this->seed(ProductCatalogSeeder::class);
        $this->seed(CatalogStructureSeeder::class);

        Sanctum::actingAs(User::factory()->create());
        $res = $this->getJson('/api/v1/subcategories?category=agro')->assertOk()->assertJsonCount(6, 'data')->assertJsonPath('has_packs', true);

        $legumes = collect($res->json('data'))->firstWhere('name', 'Légumes');
        $names = collect($this->getJson("/api/v1/products?category=agro&subcategory_id={$legumes['id']}")->json('data'))->pluck('name');
        $this->assertContains('Tomate fraîche', $names);
        $this->assertNotContains('Igname', $names);

        $packs = $this->getJson('/api/v1/products?category=agro&type=pack')->assertJsonCount(2, 'data');
        $this->assertSame('pack', $packs->json('data.0.type'));
        $this->assertNotEmpty($packs->json('data.0.items'));

        // Exécuté une seule fois : une sous-catégorie renommée par l'admin n'est pas recréée.
        Subcategory::where('name', 'Légumes')->update(['name' => 'Légumes frais']);
        $this->seed(CatalogStructureSeeder::class);
        $this->assertSame(6, Subcategory::where('category', 'agro')->count());
    }

    public function test_shopping_is_retired_and_admin_shows_food_subcategory_tabs(): void
    {
        $shopping = Product::create([
            'category' => 'shopping', 'name' => 'Pagne wax', 'price' => 15000, 'is_active' => true,
            'pickup_address' => 'Déckon', 'pickup_lat' => 6.13, 'pickup_lng' => 1.22,
        ]);
        $this->seed(ProductCatalogSeeder::class);
        $this->seed(CatalogStructureSeeder::class);
        $this->seed(FoodCatalogSeeder::class);

        // Masqué (pas supprimé : d'anciennes livraisons peuvent y être liées) et absent de l'API.
        $this->assertFalse($shopping->refresh()->is_active);
        Sanctum::actingAs(User::factory()->create());
        $this->getJson('/api/v1/products?category=shopping')->assertUnprocessable();
        $this->app['auth']->forgetGuards();

        $this->actingAs(User::factory()->admin()->create());
        $legumes = Subcategory::where('name', 'Légumes')->firstOrFail();
        $this->get('/admin/products')->assertOk()
            ->assertSee('Courses alimentaires')
            ->assertSeeInOrder(['Poissons et fruits de mer', 'Légumes', 'Céréales et conserves', 'Fruits', 'Viandes', 'Packs'])
            ->assertDontSee('Pagne wax')
            ->assertDontSee('Shopping');
        $this->get("/admin/products?subcategory={$legumes->id}")->assertOk()
            ->assertSee('Tomate fraîche')
            ->assertDontSee('Mangue');
        $this->get('/admin/products/create')->assertOk()->assertDontSee('Shopping');
    }

    public function test_food_catalog_has_the_five_requested_tabs_plus_packs(): void
    {
        // Même ordre qu'en production : catalogue, ancienne structure, puis restructuration.
        $this->seed(ProductCatalogSeeder::class);
        $this->seed(CatalogStructureSeeder::class);
        $this->seed(FoodCatalogSeeder::class);

        Sanctum::actingAs(User::factory()->create());
        $res = $this->getJson('/api/v1/subcategories?category=agro')->assertOk()->assertJsonPath('has_packs', true);
        $this->assertSame(
            ['Poissons et fruits de mer', 'Légumes', 'Céréales et conserves', 'Fruits', 'Viandes'],
            collect($res->json('data'))->pluck('name')->all(),
        );

        $products = fn (string $tab) => collect($this->getJson('/api/v1/products?category=agro&subcategory_id='
            .collect($res->json('data'))->firstWhere('name', $tab)['id'])->json('data'))->pluck('name');

        $this->assertContains('Poisson fumé', $products('Poissons et fruits de mer'));
        $this->assertContains('Crevettes fraîches', $products('Poissons et fruits de mer'));
        $this->assertContains('Poulet bicyclette', $products('Viandes'));
        $this->assertContains('Igname', $products('Légumes'));
        $this->assertContains('Riz local étuvé', $products('Céréales et conserves'));
        $this->assertContains("Sardines à l'huile (boîte)", $products('Céréales et conserves'));
        $this->assertContains('Mangue', $products('Fruits'));

        // Aucun produit alimentaire sans onglet.
        $this->assertSame(0, Product::where('category', 'agro')->where('type', 'product')->whereNull('subcategory_id')->count());
    }

    public function test_admin_renames_subcategories_and_creates_a_pack(): void
    {
        $admin = User::factory()->admin()->create();
        $sub = Subcategory::create(['category' => 'agro', 'name' => 'Céréales', 'position' => 0]);
        $riz = Product::create(['category' => 'agro', 'name' => 'Riz', 'price' => 700, 'pickup_address' => 'M', 'pickup_lat' => 6.1, 'pickup_lng' => 1.2]);

        $this->actingAs($admin)->get(route('admin.subcategories.index'))->assertOk()->assertSee('Céréales');
        $this->actingAs($admin)->put(route('admin.subcategories.update'), [
            'items' => [$sub->id => ['name' => 'Grains & céréales', 'position' => 2]],
        ])->assertSessionHasNoErrors();
        $this->assertSame('Grains & céréales', $sub->refresh()->name);

        $this->actingAs($admin)->get(route('admin.products.create', ['type' => 'pack']))->assertOk()->assertSee('Contenu du pack');
        $this->actingAs($admin)->post(route('admin.products.store'), [
            'type' => 'pack', 'category' => 'agro', 'name' => 'Pack riz', 'price' => 6000,
            'pickup_address' => 'Marché', 'pickup_lat' => 6.13, 'pickup_lng' => 1.22, 'is_active' => 1,
            'items' => [$riz->id => 10],
        ])->assertSessionHasNoErrors();

        $pack = Product::where('name', 'Pack riz')->firstOrFail();
        $this->assertTrue($pack->isPack());
        $this->assertSame(10, $pack->packItems()->first()->pivot->quantity);

        // Un pack vide est refusé.
        $this->actingAs($admin)->post(route('admin.products.store'), [
            'type' => 'pack', 'category' => 'agro', 'name' => 'Vide', 'price' => 1,
            'pickup_address' => 'M', 'pickup_lat' => 6.1, 'pickup_lng' => 1.2, 'items' => [$riz->id => 0],
        ])->assertSessionHasErrors('items');
    }

    public function test_only_visible_promotions_are_listed_and_admin_can_push(): void
    {
        $this->fakeFirebase();
        $admin = User::factory()->admin()->create();
        Promotion::create(['title' => 'Active', 'body' => 'x', 'is_active' => true]);
        Promotion::create(['title' => 'Finie', 'body' => 'x', 'is_active' => true, 'ends_at' => now()->subDay()]);
        Promotion::create(['title' => 'Masquée', 'body' => 'x', 'is_active' => false]);

        Sanctum::actingAs(User::factory()->create());
        $this->getJson('/api/v1/promotions')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.title', 'Active');
        $this->app['auth']->forgetGuards();

        $this->actingAs($admin)->post(route('admin.promotions.store'), [
            'title' => '-20 % légumes', 'body' => 'Ce week-end', 'is_active' => 1, 'send_push' => 1,
        ])->assertSessionHasNoErrors();

        Http::assertSent(fn (HttpRequest $r) => str_contains($r->url(), 'fcm.googleapis.com')
            && $r['message']['topic'] === 'clients'
            && $r['message']['notification']['title'] === '-20 % légumes');
        $this->assertNotNull(Promotion::where('title', '-20 % légumes')->first()->pushed_at);
    }

    public function test_client_sets_a_deadline(): void
    {
        $client = User::factory()->create();

        $d = $this->delivery($client, ['deadline_at' => now()->addHours(2)->toIso8601String()]);
        $this->assertNotNull($d->deadline_at);

        Sanctum::actingAs($client);
        $this->getJson("/api/v1/deliveries/{$d->id}")->assertJsonPath('data.is_urgent', false)
            ->assertJsonStructure(['data' => ['deadline_at']]);

        $this->postJson('/api/v1/deliveries', [
            'type' => 'colis', 'pickup_address' => 'Bè', 'pickup_lat' => 6.13, 'pickup_lng' => 1.24,
            'dropoff_address' => 'K', 'dropoff_lat' => 6.16, 'dropoff_lng' => 1.26,
            'recipient_name' => 'Y', 'recipient_phone' => '+22893000000',
            'deadline_at' => now()->addMinutes(5)->toIso8601String(),
        ])->assertUnprocessable()->assertJsonValidationErrors('deadline_at');
    }

    public function test_courier_is_notified_on_assignment_and_reminded_for_urgent_deliveries(): void
    {
        $this->fakeFirebase();
        $admin = User::factory()->admin()->create();
        $courier = User::factory()->courier()->create();

        Sanctum::actingAs($courier);
        $this->postJson('/api/v1/me/device-token', ['token' => 'device-abc'])->assertOk();
        $this->app['auth']->forgetGuards();

        $d = $this->delivery(User::factory()->create(), ['type' => 'express']);
        $this->actingAs($admin)->post(route('admin.deliveries.confirm-payment', $d), ['method' => 'flooz']);
        $this->actingAs($admin)->post(route('admin.deliveries.assign', $d), ['courier_id' => $courier->id])->assertSessionHasNoErrors();

        Http::assertSent(fn (HttpRequest $r) => str_contains($r->url(), 'fcm.googleapis.com')
            && $r['message']['token'] === 'device-abc'
            && str_contains($r['message']['notification']['title'], 'URGENT')
            && $r['message']['android']['notification']['channel_id'] === 'voom_urgent');

        // Route cron : clé obligatoire.
        config(['services.cron.secret' => 'cron-secret']);
        $this->postJson('/api/v1/cron/run')->assertForbidden();
        $this->postJson('/api/v1/cron/run', [], ['X-Cron-Key' => 'cron-secret'])->assertOk()->assertJsonPath('reminders_sent', 1);

        // Pas de nouveau rappel avant 10 minutes.
        $this->postJson('/api/v1/cron/run', [], ['X-Cron-Key' => 'cron-secret'])->assertJsonPath('reminders_sent', 0);
        $this->travel(11)->minutes();
        $this->postJson('/api/v1/cron/run', [], ['X-Cron-Key' => 'cron-secret'])->assertJsonPath('reminders_sent', 1);
    }

    public function test_push_is_skipped_silently_without_firebase(): void
    {
        $admin = User::factory()->admin()->create();
        $courier = User::factory()->courier()->create(['fcm_token' => 'x']);
        $d = $this->delivery(User::factory()->create(), ['type' => 'express']);
        $this->actingAs($admin)->post(route('admin.deliveries.confirm-payment', $d), ['method' => 'flooz']);

        $this->actingAs($admin)->post(route('admin.deliveries.assign', $d), ['courier_id' => $courier->id])
            ->assertSessionHasNoErrors();
        $this->assertSame('assigned', $d->refresh()->status->value);
    }
}
