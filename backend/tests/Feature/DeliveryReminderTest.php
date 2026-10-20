<?php

namespace Tests\Feature;

use App\Models\Delivery;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request as HttpRequest;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class DeliveryReminderTest extends TestCase
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

        // Heure limite proche = urgent (l'Express a été retiré de l'app).
        $d = $this->delivery(User::factory()->create(), ['deadline_at' => now()->addMinutes(35)->toIso8601String()]);
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
        $d = $this->delivery(User::factory()->create());
        $this->actingAs($admin)->post(route('admin.deliveries.confirm-payment', $d), ['method' => 'flooz']);

        $this->actingAs($admin)->post(route('admin.deliveries.assign', $d), ['courier_id' => $courier->id])
            ->assertSessionHasNoErrors();
        $this->assertSame('assigned', $d->refresh()->status->value);
    }
}
