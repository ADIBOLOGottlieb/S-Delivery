<?php

namespace Tests\Feature;

use App\Models\Delivery;
use App\Models\Payment;
use App\Models\Product;
use App\Models\Setting;
use App\Models\User;
use Database\Seeders\ProductCatalogSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class PaymentValidationTest extends TestCase
{
    use RefreshDatabase;

    private function delivery(User $client): Delivery
    {
        Sanctum::actingAs($client);
        $id = $this->postJson('/api/v1/deliveries', [
            'type' => 'colis',
            'pickup_address' => 'Bè', 'pickup_lat' => 6.1375, 'pickup_lng' => 1.24,
            'dropoff_address' => 'Kégué', 'dropoff_lat' => 6.165, 'dropoff_lng' => 1.26,
            'recipient_name' => 'Yao', 'recipient_phone' => '+22893000000',
        ])->assertCreated()->json('data.id');
        $this->app['auth']->forgetGuards();

        return Delivery::findOrFail($id);
    }

    public function test_admin_can_confirm_payment_then_assign_courier(): void
    {
        $admin = User::factory()->admin()->create();
        $courier = User::factory()->courier()->create();
        $d = $this->delivery(User::factory()->create());

        $this->actingAs($admin)
            ->get(route('admin.deliveries.show', $d))
            ->assertOk()->assertSee('Valider le paiement');

        $this->actingAs($admin)
            ->post(route('admin.deliveries.confirm-payment', $d), ['method' => 'mixx', 'reference' => 'CASH-1'])
            ->assertSessionHasNoErrors();

        $this->assertSame('verified', $d->refresh()->payment_status->value);
        $this->assertSame($admin->id, Payment::firstOrFail()->reviewed_by);

        $this->actingAs($admin)
            ->post(route('admin.deliveries.assign', $d), ['courier_id' => $courier->id])
            ->assertSessionHasNoErrors();
        $this->assertSame('assigned', $d->refresh()->status->value);

        // Déjà payée : pas de seconde validation.
        $this->actingAs($admin)
            ->post(route('admin.deliveries.confirm-payment', $d), ['method' => 'flooz'])
            ->assertSessionHasErrors('payment');
    }

    public function test_simulation_mode_validates_payment_from_the_app(): void
    {
        Setting::put(['payment_mode' => 'simulation']);
        $client = User::factory()->create();
        $d = $this->delivery($client);

        Sanctum::actingAs($client);
        $this->getJson('/api/v1/payment-info')->assertJsonPath('mode', 'gateway')->assertJsonPath('gateway', 'simulation');

        $res = $this->postJson("/api/v1/deliveries/{$d->id}/checkout", ['method' => 'flooz', 'phone' => '99000000'])
            ->assertCreated()->assertJsonPath('mode', 'redirect');
        $payment = Payment::firstOrFail();

        $this->get($res->json('redirect_url'))->assertOk()->assertSee('MODE SIMULATION');
        $this->post(route('checkout.simulate', $payment->checkout_token), ['result' => 'success'])
            ->assertOk()->assertSee('Paiement confirmé');

        $this->getJson("/api/v1/deliveries/{$d->id}/payments/{$payment->id}")
            ->assertJsonPath('payment.status', 'verified')
            ->assertJsonPath('delivery.payment_status', 'verified');
    }

    public function test_simulation_is_refused_once_mode_is_switched_off(): void
    {
        Setting::put(['payment_mode' => 'simulation']);
        $client = User::factory()->create();
        $d = $this->delivery($client);
        Sanctum::actingAs($client);
        $this->postJson("/api/v1/deliveries/{$d->id}/checkout", ['method' => 'flooz', 'phone' => '99000000'])->assertCreated();
        $token = Payment::firstOrFail()->checkout_token;

        Setting::put(['payment_mode' => 'manual']);
        $this->post(route('checkout.simulate', $token), ['result' => 'success'])->assertOk();

        $this->assertSame('unpaid', $d->refresh()->payment_status->value);
    }

    public function test_admin_can_switch_payment_mode(): void
    {
        $admin = User::factory()->admin()->create();
        $this->actingAs($admin)->get(route('admin.settings.edit'))->assertOk()->assertSee('Mode de paiement');

        $this->actingAs($admin)->put(route('admin.settings.update'), [
            'merchant_name' => 'VOOM Delivery', 'base_fee' => 500, 'per_km_fee' => 150,
            'express_fee' => 1000, 'min_fee' => 1000, 'payment_mode' => 'simulation',
        ])->assertSessionHasNoErrors();

        $this->assertSame('simulation', Setting::get('payment_mode'));
    }

    public function test_catalog_is_seeded_once_with_food_products_only(): void
    {
        $this->seed(ProductCatalogSeeder::class);

        $this->assertSame(0, Product::where('category', 'shopping')->count());
        $this->assertGreaterThanOrEqual(35, Product::where('category', 'agro')->count());
        $this->assertTrue(Product::where('name', 'Maïs jaune (grain)')->exists());

        // L'admin supprime un produit : il ne réapparaît pas au prochain déploiement.
        Product::where('name', 'Maïs jaune (grain)')->delete();
        $this->seed(ProductCatalogSeeder::class);
        $this->assertFalse(Product::where('name', 'Maïs jaune (grain)')->exists());
    }
}
