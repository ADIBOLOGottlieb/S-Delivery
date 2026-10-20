<?php

namespace Tests\Feature;

use App\Models\Delivery;
use App\Models\User;
use App\Services\PushNotifier;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/** Discussion de la course, position du livreur en direct, code de remise et note. */
class DeliveryChatTrackingTest extends TestCase
{
    use RefreshDatabase;

    /** @var list<array{user: int, title: string, data: array}> */
    private array $pushes = [];

    protected function setUp(): void
    {
        parent::setUp();
        $this->app->instance(PushNotifier::class, new class($this->pushes) extends PushNotifier
        {
            public function __construct(private array &$log) {}

            public function toUser(User $user, string $title, string $body, array $data = [], bool $urgent = false): bool
            {
                $this->log[] = ['user' => $user->id, 'title' => $title, 'data' => $data];

                return true;
            }
        });
    }

    /** Livraison payée et assignée à [courier]. */
    private function assigned(User $client, User $courier): Delivery
    {
        Sanctum::actingAs($client);
        $id = $this->postJson('/api/v1/deliveries', [
            'type' => 'colis',
            'pickup_address' => 'Bè', 'pickup_lat' => 6.1375, 'pickup_lng' => 1.24,
            'dropoff_address' => 'Kégué', 'dropoff_lat' => 6.165, 'dropoff_lng' => 1.26,
            'recipient_name' => 'Yao', 'recipient_phone' => '+22893000000',
        ])->assertCreated()->json('data.id');
        $this->app['auth']->forgetGuards();

        $admin = User::factory()->admin()->create();
        $this->actingAs($admin)->post(route('admin.deliveries.confirm-payment', $id), ['method' => 'flooz']);
        $this->actingAs($admin)->post(route('admin.deliveries.assign', $id), ['courier_id' => $courier->id])->assertSessionHasNoErrors();
        $this->app['auth']->forgetGuards();
        $this->pushes = [];

        return Delivery::findOrFail($id);
    }

    public function test_client_and_courier_chat_with_unread_counts_and_push(): void
    {
        $client = User::factory()->create();
        $courier = User::factory()->courier()->create();
        $d = $this->assigned($client, $courier);

        Sanctum::actingAs($client);
        $this->postJson("/api/v1/deliveries/{$d->id}/messages", ['body' => 'Le portail est bleu'])
            ->assertCreated()->assertJsonPath('data.from', 'client')->assertJsonPath('data.is_mine', true);
        $this->postJson("/api/v1/deliveries/{$d->id}/messages", [])->assertUnprocessable();

        Sanctum::actingAs($courier);
        $this->getJson("/api/v1/courier/deliveries/{$d->id}")->assertJsonPath('data.unread_messages', 1);
        $this->getJson("/api/v1/courier/deliveries/{$d->id}/messages")
            ->assertOk()->assertJsonPath('chat_open', true)
            ->assertJsonPath('data.0.body', 'Le portail est bleu')
            ->assertJsonPath('data.0.is_mine', false);
        $this->getJson("/api/v1/courier/deliveries/{$d->id}")->assertJsonPath('data.unread_messages', 0);

        $this->post("/api/v1/courier/deliveries/{$d->id}/messages", ['photo' => UploadedFile::fake()->image('devant.jpg')], ['Accept' => 'application/json'])
            ->assertCreated()->assertJsonPath('data.from', 'courier');
        $this->postJson("/api/v1/courier/deliveries/{$d->id}/messages", ['lat' => 6.16, 'lng' => 1.25])->assertCreated();

        // Chaque message prévient l'autre partie, et ouvre la discussion de la course.
        $this->assertSame([$courier->id, $client->id, $client->id], array_column($this->pushes, 'user'));
        $this->assertSame(['type' => 'delivery_chat', 'delivery_id' => (string) $d->id], $this->pushes[1]['data']);

        Sanctum::actingAs($client);
        $this->getJson("/api/v1/deliveries/{$d->id}")->assertJsonPath('data.unread_messages', 2);

        // L'agence voit tout et peut répondre depuis la fiche.
        $admin = User::factory()->admin()->create();
        $this->app['auth']->forgetGuards();
        $this->actingAs($admin)->get(route('admin.deliveries.show', $d))->assertOk()->assertSee('Le portail est bleu');
        $this->actingAs($admin)->post(route('admin.deliveries.message', $d), ['body' => 'Bien noté'])->assertSessionHasNoErrors();
        Sanctum::actingAs($client);
        $this->getJson("/api/v1/deliveries/{$d->id}/messages")->assertJsonPath('data.3.from', 'agency');
    }

    public function test_chat_is_restricted_to_participants_and_closes_after_the_delivery(): void
    {
        $client = User::factory()->create();
        $courier = User::factory()->courier()->create();
        $other = User::factory()->courier()->create();
        $d = $this->assigned($client, $courier);

        Sanctum::actingAs($other);
        $this->getJson("/api/v1/courier/deliveries/{$d->id}/messages")->assertNotFound();
        $this->postJson("/api/v1/courier/deliveries/{$d->id}/messages", ['body' => 'x'])->assertNotFound();
        Sanctum::actingAs(User::factory()->create());
        $this->getJson("/api/v1/deliveries/{$d->id}/messages")->assertNotFound();

        // Livrée : le livreur ne peut plus écrire, le client peut encore signaler un souci.
        Sanctum::actingAs($courier);
        $this->postJson("/api/v1/courier/deliveries/{$d->id}/status", ['status' => 'picked_up'])->assertOk();
        $this->postJson("/api/v1/courier/deliveries/{$d->id}/status", ['status' => 'delivered', 'code' => $d->refresh()->dropoff_code])->assertOk();
        $this->postJson("/api/v1/courier/deliveries/{$d->id}/messages", ['body' => 'Merci'])
            ->assertUnprocessable()->assertJsonValidationErrors('body');

        Sanctum::actingAs($client);
        $this->getJson("/api/v1/deliveries/{$d->id}/messages")
            ->assertJsonPath('chat_open', true)
            // Messages système : colis récupéré puis remis.
            ->assertJsonPath('data.0.from', 'system')
            ->assertJsonCount(2, 'data');
        $this->postJson("/api/v1/deliveries/{$d->id}/messages", ['body' => 'Colis abîmé'])->assertCreated();
    }

    public function test_courier_location_is_shared_with_the_client_only_during_the_ride(): void
    {
        $client = User::factory()->create();
        $courier = User::factory()->courier()->create();
        $d = $this->assigned($client, $courier);

        Sanctum::actingAs($courier);
        $this->postJson('/api/v1/courier/location', ['lat' => 6.15, 'lng' => 1.25])->assertOk();
        $this->postJson('/api/v1/courier/location', ['lat' => 200, 'lng' => 1.25])->assertUnprocessable();

        Sanctum::actingAs($client);
        $this->getJson("/api/v1/deliveries/{$d->id}")
            ->assertJsonPath('data.courier.location.lat', 6.15)
            ->assertJsonPath('data.courier.location.lng', 1.25);

        // Position trop ancienne : plus affichée.
        $courier->forceFill(['located_at' => now()->subMinutes(30)])->save();
        $this->getJson("/api/v1/deliveries/{$d->id}")->assertJsonPath('data.courier.location', null);

        // Seuls les livreurs envoient leur position.
        $this->postJson('/api/v1/courier/location', ['lat' => 6.15, 'lng' => 1.25])->assertForbidden();
    }

    public function test_dropoff_code_is_shown_to_the_client_until_delivery(): void
    {
        $client = User::factory()->create();
        $courier = User::factory()->courier()->create();
        $d = $this->assigned($client, $courier);

        Sanctum::actingAs($client);
        $this->getJson("/api/v1/deliveries/{$d->id}")->assertJsonPath('data.dropoff_code', $d->dropoff_code);

        Sanctum::actingAs($courier);
        $this->postJson("/api/v1/courier/deliveries/{$d->id}/status", ['status' => 'picked_up'])->assertOk();
        $this->postJson("/api/v1/courier/deliveries/{$d->id}/status", ['status' => 'delivered', 'code' => " {$d->dropoff_code} "])->assertOk();

        Sanctum::actingAs($client);
        $this->getJson("/api/v1/deliveries/{$d->id}")->assertJsonPath('data.dropoff_code', null);

        // Anciennes livraisons sans code : la remise reste possible sans code.
        $legacy = $this->assigned($client, $courier);
        $legacy->forceFill(['dropoff_code' => null])->save();
        Sanctum::actingAs($courier);
        $this->postJson("/api/v1/courier/deliveries/{$legacy->id}/status", ['status' => 'picked_up'])->assertOk();
        $this->postJson("/api/v1/courier/deliveries/{$legacy->id}/status", ['status' => 'delivered'])->assertOk();
    }

    public function test_client_rates_the_courier_once_after_delivery(): void
    {
        $client = User::factory()->create();
        $courier = User::factory()->courier()->create();
        $d = $this->assigned($client, $courier);

        Sanctum::actingAs($client);
        $this->postJson("/api/v1/deliveries/{$d->id}/rating", ['rating' => 5])
            ->assertUnprocessable()->assertJsonValidationErrors('rating');

        Sanctum::actingAs($courier);
        $this->postJson("/api/v1/courier/deliveries/{$d->id}/status", ['status' => 'picked_up'])->assertOk();
        $this->postJson("/api/v1/courier/deliveries/{$d->id}/status", ['status' => 'delivered', 'code' => $d->refresh()->dropoff_code])->assertOk();

        Sanctum::actingAs($client);
        $this->getJson("/api/v1/deliveries/{$d->id}")->assertJsonPath('data.can_rate', true);
        $this->postJson("/api/v1/deliveries/{$d->id}/rating", ['rating' => 6])->assertUnprocessable();
        $this->postJson("/api/v1/deliveries/{$d->id}/rating", ['rating' => 4, 'comment' => '  Rapide et poli '])
            ->assertOk()
            ->assertJsonPath('data.rating', 4)
            ->assertJsonPath('data.rating_comment', 'Rapide et poli')
            ->assertJsonPath('data.can_rate', false);
        $this->postJson("/api/v1/deliveries/{$d->id}/rating", ['rating' => 1])
            ->assertUnprocessable()->assertJsonPath('errors.rating.0', 'Vous avez déjà noté cette livraison.');

        $this->app['auth']->forgetGuards();
        $this->actingAs(User::factory()->admin()->create())->get(route('admin.deliveries.show', $d))->assertOk()->assertSee('Rapide et poli');
    }
}
