<?php

namespace Tests\Feature;

use App\Models\Delivery;
use App\Models\Payment;
use App\Models\Setting;
use App\Models\User;
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

    public function test_payment_info_lists_only_configured_merchant_numbers(): void
    {
        Setting::put(['flooz_merchant_number' => '99 00 00 00', 'mixx_merchant_number' => null]);
        Sanctum::actingAs(User::factory()->create());

        $this->getJson('/api/v1/payment-info')
            ->assertOk()
            ->assertJsonCount(1, 'methods')
            ->assertJsonPath('methods.0.method', 'flooz')
            ->assertJsonPath('methods.0.merchant_number', '99 00 00 00')
            ->assertJsonMissingPath('mode');
    }

    public function test_without_gateway_keys_the_app_falls_back_to_manual_payment(): void
    {
        config(['payments.gateway' => 'kkiapay', 'payments.kkiapay.public_key' => null]);
        $client = User::factory()->create();
        $d = $this->delivery($client);
        Sanctum::actingAs($client);

        $this->getJson('/api/v1/payment-info')->assertOk()->assertJsonPath('online.enabled', false);
        $this->postJson("/api/v1/deliveries/{$d->id}/checkout", ['method' => 'flooz', 'phone' => '99000000'])
            ->assertUnprocessable()->assertJsonValidationErrors('payment');
    }

    public function test_admin_settings_show_payment_mode_and_merchant_numbers(): void
    {
        $admin = User::factory()->admin()->create();
        $this->actingAs($admin)->get(route('admin.settings.edit'))->assertOk()
            ->assertSee('Paiement intégré')
            ->assertSee('Mode de paiement')
            ->assertSee(route('webhooks.kkiapay'));

        $this->actingAs($admin)->put(route('admin.settings.update'), [
            'merchant_name' => 'S-Delivery', 'flooz_merchant_number' => '99112233', 'payment_mode' => 'manual',
            'base_fee' => 500, 'per_km_fee' => 150, 'express_fee' => 1000, 'min_fee' => 1000,
        ])->assertSessionHasNoErrors();

        $this->assertSame('99112233', Setting::get('flooz_merchant_number'));
        $this->assertSame('manual', Setting::get('payment_mode'));
    }

    public function test_card_cannot_be_paid_by_screenshot(): void
    {
        $client = User::factory()->create();
        $d = $this->delivery($client);
        Sanctum::actingAs($client);

        $this->post("/api/v1/deliveries/{$d->id}/payment", [
            'method' => 'card', 'transaction_ref' => 'CB1', 'payer_phone' => '+22899000000',
            'screenshot' => \Illuminate\Http\UploadedFile::fake()->image('c.jpg'),
        ], ['Accept' => 'application/json'])->assertUnprocessable()->assertJsonValidationErrors('method');
    }
}
