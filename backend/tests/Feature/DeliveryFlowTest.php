<?php

namespace Tests\Feature;

use App\Models\Delivery;
use App\Models\Payment;
use App\Models\Product;
use App\Models\Setting;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class DeliveryFlowTest extends TestCase
{
    use RefreshDatabase;

    private function deliveryPayload(array $overrides = []): array
    {
        return [
            'type' => 'colis',
            'pickup_address' => 'Bè, Lomé',
            'pickup_lat' => 6.1375,
            'pickup_lng' => 1.2400,
            'dropoff_address' => 'Kégué, Lomé',
            'dropoff_lat' => 6.1650,
            'dropoff_lng' => 1.2600,
            'recipient_name' => 'Yao',
            'recipient_phone' => '+22893000000',
            'package_description' => 'Carton de documents',
            ...$overrides,
        ];
    }

    public function test_public_registration_always_creates_a_client(): void
    {
        $response = $this->postJson('/api/v1/register', [
            'name' => 'Afi',
            'phone_number' => '+22890112233',
            'password' => 'password123',
            'password_confirmation' => 'password123',
            'role' => 'admin',
        ]);

        $response->assertCreated()->assertJsonPath('user.role', 'client')->assertJsonStructure(['token']);
    }

    public function test_login_with_phone_and_inactive_or_admin_accounts_are_refused(): void
    {
        $client = User::factory()->create(['password' => 'password123']);
        $this->postJson('/api/v1/login', ['login' => $client->phone_number, 'password' => 'password123'])
            ->assertOk()->assertJsonPath('user.id', $client->id);

        $inactive = User::factory()->courier()->create(['password' => 'password123', 'is_active' => false]);
        $this->postJson('/api/v1/login', ['login' => $inactive->email, 'password' => 'password123'])
            ->assertUnprocessable();

        $admin = User::factory()->admin()->create(['password' => 'password123']);
        $this->postJson('/api/v1/login', ['login' => $admin->email, 'password' => 'password123'])
            ->assertUnprocessable();
    }

    public function test_full_flow_from_request_to_delivery(): void
    {
        Storage::fake('local');
        Setting::put(['base_fee' => '500', 'per_km_fee' => '100', 'express_fee' => '1000', 'min_fee' => '1000']);

        $client = User::factory()->create();
        $courier = User::factory()->courier()->create();
        $admin = User::factory()->admin()->create();

        // 1. Le client crée la demande A -> B
        Sanctum::actingAs($client);
        $id = $this->postJson('/api/v1/deliveries', $this->deliveryPayload())
            ->assertCreated()
            ->assertJsonPath('data.status', 'pending')
            ->assertJsonPath('data.payment_status', 'unpaid')
            ->assertJsonPath('data.can_pay', true)
            ->json('data.id');

        $delivery = Delivery::findOrFail($id);
        $this->assertGreaterThanOrEqual(1000, $delivery->delivery_fee);
        $this->assertSame($delivery->delivery_fee, $delivery->total_amount);

        // 2. Le client envoie la capture d'écran du paiement Flooz
        $this->post("/api/v1/deliveries/{$id}/payment", [
            'method' => 'flooz',
            'transaction_ref' => 'FLZ123456',
            'payer_phone' => '+22899000000',
            'screenshot' => UploadedFile::fake()->image('capture.jpg'),
        ], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonPath('data.payment_status', 'submitted');

        // Capture stockée en base (le disque Render est effacé à chaque redéploiement).
        $payment = Payment::firstOrFail();
        $this->assertNull($payment->screenshot_path);
        $this->assertNotNull($payment->screenshot_media_id);
        $this->assertSame([], Storage::disk('local')->allFiles());

        // 3. L'admin ne peut pas assigner avant validation, puis valide et assigne
        $this->actingAs($admin)
            ->post(route('admin.deliveries.assign', $id), ['courier_id' => $courier->id])
            ->assertSessionHasErrors('courier_id');

        $this->actingAs($admin)->post(route('admin.payments.approve', $payment))->assertRedirect();
        $this->actingAs($admin)
            ->post(route('admin.deliveries.assign', $id), ['courier_id' => $courier->id])
            ->assertSessionHasNoErrors();

        // 4. Le livreur voit la livraison assignée, la récupère puis la livre
        Sanctum::actingAs($courier);
        $this->getJson('/api/v1/courier/deliveries')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.pickup.lat', 6.1375)
            ->assertJsonPath('data.0.dropoff.contact_phone', '+22893000000');

        $this->postJson("/api/v1/courier/deliveries/{$id}/status", ['status' => 'delivered'])
            ->assertUnprocessable();
        $this->postJson("/api/v1/courier/deliveries/{$id}/status", ['status' => 'picked_up'])
            ->assertOk()->assertJsonPath('data.status', 'picked_up');
        $this->postJson("/api/v1/courier/deliveries/{$id}/status", ['status' => 'delivered'])
            ->assertOk()->assertJsonPath('data.status', 'delivered');

        $this->getJson('/api/v1/courier/deliveries?scope=history')->assertJsonCount(1, 'data');
    }

    public function test_access_is_isolated_between_users_and_roles(): void
    {
        $owner = User::factory()->create();
        $other = User::factory()->create();
        $courier = User::factory()->courier()->create();

        Sanctum::actingAs($owner);
        $id = $this->postJson('/api/v1/deliveries', $this->deliveryPayload())->json('data.id');

        Sanctum::actingAs($other);
        $this->getJson("/api/v1/deliveries/{$id}")->assertNotFound();

        Sanctum::actingAs($courier);
        $this->getJson("/api/v1/courier/deliveries/{$id}")->assertNotFound(); // non assignée à ce livreur
        $this->postJson('/api/v1/deliveries', $this->deliveryPayload())->assertForbidden();

        Sanctum::actingAs($owner);
        $this->getJson('/api/v1/courier/deliveries')->assertForbidden();

        // Panneau admin inaccessible aux non-admins
        $this->actingAs($owner)->get('/admin')->assertForbidden();
    }

    public function test_marketplace_order_uses_vendor_location_and_adds_items_amount(): void
    {
        $product = Product::create([
            'category' => 'agro', 'name' => 'Tomates', 'price' => 800, 'unit' => 'kg',
            'pickup_address' => 'Marché', 'pickup_lat' => 6.13, 'pickup_lng' => 1.22, 'is_active' => true,
        ]);

        Sanctum::actingAs(User::factory()->create());
        $this->getJson('/api/v1/products?category=agro')->assertJsonCount(1, 'data');

        $payload = $this->deliveryPayload(['product_id' => $product->id, 'quantity' => 3]);
        unset($payload['pickup_address'], $payload['pickup_lat'], $payload['pickup_lng']);

        $response = $this->postJson('/api/v1/deliveries', $payload)->assertCreated();

        $response->assertJsonPath('data.items_amount', 2400)
            ->assertJsonPath('data.pickup.address', 'Marché');
        $this->assertSame(2400 + $response->json('data.delivery_fee'), $response->json('data.total_amount'));
    }

    public function test_admin_pages_render(): void
    {
        Storage::fake('local');
        $this->seed();
        $admin = User::where('role', 'admin')->firstOrFail();

        Sanctum::actingAs(User::where('role', 'client')->firstOrFail());
        $id = $this->postJson('/api/v1/deliveries', $this->deliveryPayload())->json('data.id');
        $this->post("/api/v1/deliveries/{$id}/payment", [
            'method' => 'flooz', 'transaction_ref' => 'R1', 'payer_phone' => '+22899000000',
            'screenshot' => UploadedFile::fake()->image('c.jpg'),
        ], ['Accept' => 'application/json'])->assertOk();

        $this->app['auth']->forgetGuards();
        $this->get('/admin')->assertRedirect(route('admin.login'));
        $this->get(route('admin.login'))->assertOk();

        $this->actingAs($admin);
        foreach (['admin.dashboard', 'admin.deliveries.index', 'admin.couriers.index', 'admin.couriers.create',
            'admin.clients.index', 'admin.products.index', 'admin.products.create', 'admin.settings.edit'] as $route) {
            $this->get(route($route))->assertOk();
        }
        $this->get(route('admin.deliveries.show', $id))->assertOk()->assertSee('Confirmer le paiement');
        $this->get(route('admin.payments.screenshot', Payment::firstOrFail()))->assertOk();
        $this->get(route('admin.couriers.edit', User::where('role', 'livreur')->first()))->assertOk();
        $this->get(route('admin.products.edit', Product::first()))->assertOk();
    }

    public function test_payment_of_cancelled_delivery_cannot_be_approved(): void
    {
        Storage::fake('local');
        $admin = User::factory()->admin()->create();
        Sanctum::actingAs(User::factory()->create());

        $id = $this->postJson('/api/v1/deliveries', $this->deliveryPayload())->json('data.id');
        $this->post("/api/v1/deliveries/{$id}/payment", [
            'method' => 'flooz', 'transaction_ref' => 'C1', 'payer_phone' => '+22899000000',
            'screenshot' => UploadedFile::fake()->image('c.jpg'),
        ], ['Accept' => 'application/json'])->assertOk();
        Delivery::findOrFail($id)->cancel('Test');

        $this->app['auth']->forgetGuards();
        $this->actingAs($admin)
            ->post(route('admin.payments.approve', Payment::firstOrFail()))
            ->assertSessionHasErrors('payment');
        $this->assertSame('submitted', Delivery::findOrFail($id)->payment_status->value);
    }

    public function test_transaction_reference_cannot_be_reused(): void
    {
        Storage::fake('local');
        Sanctum::actingAs(User::factory()->create());

        $first = $this->postJson('/api/v1/deliveries', $this->deliveryPayload())->json('data.id');
        $second = $this->postJson('/api/v1/deliveries', $this->deliveryPayload())->json('data.id');

        $pay = fn ($id) => $this->post("/api/v1/deliveries/{$id}/payment", [
            'method' => 'mixx',
            'transaction_ref' => 'MX-1',
            'payer_phone' => '+22870000000',
            'screenshot' => UploadedFile::fake()->image('c.png'),
        ], ['Accept' => 'application/json']);

        $pay($first)->assertOk();
        $pay($second)->assertUnprocessable()->assertJsonValidationErrors('transaction_ref');
    }
}
