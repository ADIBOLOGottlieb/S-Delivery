<?php

namespace Tests\Feature;

use App\Http\Controllers\Admin\RequestController;
use App\Models\Delivery;
use App\Models\DeliveryRequest;
use App\Models\Payment;
use App\Models\Product;
use App\Models\User;
use App\Services\PushNotifier;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/** Paiements, annulations, notifications et demandes photo : cohérence du cycle de vie d'une livraison. */
class DeliveryConsistencyTest extends TestCase
{
    use RefreshDatabase;

    /** @var array<int, array{user: int, title: string, body: string, data: array<string, string>}> */
    private array $pushes = [];

    protected function setUp(): void
    {
        parent::setUp();

        $pushes = &$this->pushes;
        $this->app->instance(PushNotifier::class, new class($pushes) extends PushNotifier
        {
            public function __construct(private array &$log)
            {
                parent::__construct();
            }

            public function toUser(User $user, string $title, string $body, array $data = [], bool $urgent = false): bool
            {
                $this->log[] = ['user' => $user->id, 'title' => $title, 'body' => $body, 'data' => $data];

                return true;
            }
        });
    }

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

    private function delivery(User $client): Delivery
    {
        Sanctum::actingAs($client);
        $id = $this->postJson('/api/v1/deliveries', $this->payload())->assertCreated()->json('data.id');
        $this->app['auth']->forgetGuards();

        return Delivery::findOrFail($id);
    }

    private function submitProof(User $client, Delivery $delivery, string $ref = 'FLZ1')
    {
        Sanctum::actingAs($client);
        $response = $this->post("/api/v1/deliveries/{$delivery->id}/payment", [
            'method' => 'flooz', 'transaction_ref' => $ref, 'payer_phone' => '+22899000000',
            'screenshot' => UploadedFile::fake()->image('capture.jpg'),
        ], ['Accept' => 'application/json']);
        $this->app['auth']->forgetGuards();

        return $response;
    }

    /** @return array<int, array<string, string>> data des pushes reçus par cet utilisateur */
    private function pushesTo(User $user): array
    {
        return collect($this->pushes)->where('user', $user->id)->pluck('data')->all();
    }

    public function test_client_and_couriers_are_notified_through_the_delivery_lifecycle(): void
    {
        $admin = User::factory()->admin()->create();
        $client = User::factory()->create();
        $first = User::factory()->courier()->create();
        $second = User::factory()->courier()->create();
        $d = $this->delivery($client);
        $expected = ['type' => 'delivery', 'delivery_id' => (string) $d->id];

        $this->submitProof($client, $d)->assertOk();
        $this->actingAs($admin)->post(route('admin.payments.reject', Payment::firstOrFail()), ['rejection_reason' => 'Montant incorrect'])
            ->assertSessionHasNoErrors();
        $this->assertStringContainsString('Montant incorrect', collect($this->pushes)->last()['body']);

        $this->submitProof($client, $d, 'FLZ2')->assertOk();
        $this->actingAs($admin)->post(route('admin.payments.approve', Payment::latest('id')->first()))->assertSessionHasNoErrors();
        $this->actingAs($admin)->post(route('admin.deliveries.assign', $d), ['courier_id' => $first->id])->assertSessionHasNoErrors();
        $this->actingAs($admin)->post(route('admin.deliveries.assign', $d), ['courier_id' => $second->id])->assertSessionHasNoErrors();

        Sanctum::actingAs($second);
        $this->postJson("/api/v1/courier/deliveries/{$d->id}/status", ['status' => 'picked_up'])->assertOk();
        $this->postJson("/api/v1/courier/deliveries/{$d->id}/status", ['status' => 'delivered'])->assertOk();

        // Client : refus, confirmation, livreur (x2), récupéré, livré — toujours exactement {type, delivery_id}.
        $this->assertSame(array_fill(0, 6, $expected), $this->pushesTo($client));
        $this->assertSame([
            [...$expected, 'kind' => 'assigned'],
            [...$expected, 'kind' => 'unassigned'],
        ], $this->pushesTo($first));
        $this->assertSame([[...$expected, 'kind' => 'assigned']], $this->pushesTo($second));
    }

    public function test_admin_cancel_of_paid_delivery_notifies_and_flags_refund(): void
    {
        $admin = User::factory()->admin()->create();
        $client = User::factory()->create();
        $courier = User::factory()->courier()->create();
        $d = $this->delivery($client);

        $this->actingAs($admin)->post(route('admin.deliveries.confirm-payment', $d), ['method' => 'mixx']);
        $this->actingAs($admin)->post(route('admin.deliveries.assign', $d), ['courier_id' => $courier->id]);
        $this->actingAs($admin)->post(route('admin.deliveries.cancel', $d), ['reason' => 'Client injoignable'])
            ->assertSessionHas('success', fn ($m) => str_contains($m, 'remboursez'));

        $d->refresh();
        $this->assertTrue($d->needsRefund());
        $this->assertSame('verified', $d->payment_status->value);
        $this->assertSame(['type' => 'delivery', 'delivery_id' => (string) $d->id, 'kind' => 'cancelled'], last($this->pushesTo($courier)));
        $this->assertSame(['type' => 'delivery', 'delivery_id' => (string) $d->id], last($this->pushesTo($client)));
        $this->assertStringContainsString('remboursé', collect($this->pushes)->where('user', $client->id)->last()['body']);

        $this->get(route('admin.deliveries.show', $d))->assertOk()->assertSee('À rembourser');
        $this->get(route('admin.deliveries.index'))->assertOk()->assertSee('À rembourser');
    }

    public function test_rejecting_a_duplicate_proof_never_unpays_a_verified_delivery(): void
    {
        $admin = User::factory()->admin()->create();
        $client = User::factory()->create();
        $d = $this->delivery($client);
        $this->submitProof($client, $d)->assertOk();

        // Doublon arrivé par une ancienne requête concurrente.
        $duplicate = $d->payments()->create([
            'method' => 'mixx', 'transaction_ref' => 'MX9', 'payer_phone' => '+22899000000',
            'amount' => $d->total_amount, 'status' => 'submitted',
        ]);
        $proof = Payment::where('transaction_ref', 'FLZ1')->firstOrFail();

        $this->actingAs($admin)->post(route('admin.payments.approve', $proof))->assertSessionHasNoErrors();
        // Approuver le doublon est refusé, le refuser laisse la livraison payée.
        $this->actingAs($admin)->post(route('admin.payments.approve', $duplicate))->assertSessionHasErrors('payment');
        $this->actingAs($admin)->post(route('admin.payments.reject', $duplicate), ['rejection_reason' => 'Doublon'])
            ->assertSessionHasNoErrors();

        $this->assertSame('verified', $d->refresh()->payment_status->value);
        $this->assertSame('rejected', $duplicate->refresh()->status->value);
        // Déjà traité : pas de seconde décision.
        $this->actingAs($admin)->post(route('admin.payments.reject', $proof), ['rejection_reason' => 'x'])->assertSessionHasErrors('payment');
    }

    public function test_client_cannot_cancel_once_proof_is_sent(): void
    {
        $client = User::factory()->create();
        $d = $this->delivery($client);

        Sanctum::actingAs($client);
        $this->getJson("/api/v1/deliveries/{$d->id}")->assertJsonPath('data.can_cancel', true);
        $this->submitProof($client, $d)->assertOk()->assertJsonPath('data.can_cancel', false);

        Sanctum::actingAs($client);
        $this->postJson("/api/v1/deliveries/{$d->id}/cancel")
            ->assertUnprocessable()
            ->assertJsonPath('errors.status.0', fn ($m) => str_contains($m, 'en cours de vérification'));
        $this->assertSame('pending', $d->refresh()->status->value);
    }

    public function test_transaction_reference_is_normalized_and_screenshot_kept_in_database(): void
    {
        Storage::fake('local');
        $admin = User::factory()->admin()->create();
        $client = User::factory()->create();
        $first = $this->delivery($client);
        $second = $this->delivery($client);

        $this->submitProof($client, $first, '  flz 12 ab ')->assertOk();
        $payment = Payment::firstOrFail();
        $this->assertSame('FLZ12AB', $payment->transaction_ref);
        $this->assertNotNull($payment->screenshot_media_id);

        $this->submitProof($client, $second, 'Flz12Ab')->assertUnprocessable()->assertJsonValidationErrors('transaction_ref');

        $this->actingAs($admin)->get(route('admin.payments.screenshot', $payment))
            ->assertOk()->assertHeader('Content-Type', 'image/jpeg');

        // Ancienne capture encore sur disque : toujours servie.
        Storage::disk('local')->put('payments/old.jpg', 'legacy');
        $legacy = $second->payments()->create([
            'method' => 'mixx', 'transaction_ref' => 'OLD1', 'payer_phone' => '+22899000000',
            'amount' => 1000, 'screenshot_path' => 'payments/old.jpg', 'status' => 'rejected',
        ]);
        $this->get(route('admin.payments.screenshot', $legacy))->assertOk();
        $this->get(route('admin.deliveries.show', $second))->assertOk()->assertSee(route('admin.payments.screenshot', $legacy));
    }

    public function test_product_order_calls_the_vendor_not_the_client(): void
    {
        $product = Product::create([
            'category' => 'agro', 'name' => 'Tomates', 'price' => 800, 'unit' => 'kg', 'vendor_name' => 'Mama Tomates',
            'vendor_phone' => '+22890000001', 'pickup_address' => 'Marché', 'pickup_lat' => 6.13, 'pickup_lng' => 1.22, 'is_active' => true,
        ]);
        $silent = Product::create([
            'category' => 'agro', 'name' => 'Oignons', 'price' => 500, 'unit' => 'kg',
            'pickup_address' => 'Marché', 'pickup_lat' => 6.13, 'pickup_lng' => 1.22, 'is_active' => true,
        ]);
        $payload = fn (Product $p) => collect($this->payload(['product_id' => $p->id, 'quantity' => 1]))
            ->except(['pickup_address', 'pickup_lat', 'pickup_lng'])->all();

        Sanctum::actingAs(User::factory()->create());
        $this->postJson('/api/v1/deliveries', $payload($product))->assertCreated()
            ->assertJsonPath('data.pickup.contact_name', 'Mama Tomates')
            ->assertJsonPath('data.pickup.contact_phone', '+22890000001');
        $this->postJson('/api/v1/deliveries', $payload($silent))->assertCreated()
            ->assertJsonPath('data.pickup.contact_name', null)
            ->assertJsonPath('data.pickup.contact_phone', null);

        $silent->update(['is_active' => false]);
        $this->postJson('/api/v1/deliveries', $payload($silent))->assertUnprocessable()
            ->assertJsonPath('errors.product_id.0', "Ce produit n'est plus disponible.");
    }

    public function test_express_is_refused_by_the_app_and_deadline_must_follow_schedule(): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->postJson('/api/v1/deliveries', $this->payload(['type' => 'express']))
            ->assertUnprocessable()->assertJsonPath('errors.type.0', fn ($m) => str_contains($m, 'Express'));
        $this->postJson('/api/v1/deliveries/quote', $this->payload(['type' => 'express']))
            ->assertUnprocessable()->assertJsonValidationErrors('type');

        $this->postJson('/api/v1/deliveries', $this->payload([
            'type' => 'programmee',
            'scheduled_at' => now()->addHours(5)->toIso8601String(),
            'deadline_at' => now()->addHours(2)->toIso8601String(),
        ]))->assertUnprocessable()->assertJsonPath('errors.deadline_at.0', "L'heure limite doit être après l'heure de passage programmée.");

        $this->postJson('/api/v1/deliveries', $this->payload(['type' => 'programmee']))
            ->assertUnprocessable()->assertJsonPath('errors.scheduled_at.0', "Choisissez la date et l'heure de passage.");

        $this->postJson('/api/v1/deliveries', $this->payload([
            'type' => 'programmee',
            'scheduled_at' => now()->addHours(2)->toIso8601String(),
            'deadline_at' => now()->addHours(4)->toIso8601String(),
        ]))->assertCreated();
    }

    public function test_photo_request_lifecycle_reschedule_unread_and_close(): void
    {
        $admin = User::factory()->admin()->create();
        $client = User::factory()->create();
        $request = $client->deliveryRequests()->create(['parcel_amount' => 12000]);
        $request->post($client, ['body' => 'Bonjour']);

        // Une commande de produit ne sert pas à pré-remplir le point A.
        $client->deliveries()->create([...$this->payload(['pickup_address' => 'Boutique Bè']), 'distance_km' => 3, 'delivery_fee' => 1000, 'total_amount' => 1000]);
        $product = Product::create(['category' => 'agro', 'name' => 'Riz', 'price' => 100, 'unit' => 'kg',
            'pickup_address' => 'Grand marché', 'pickup_lat' => 6.13, 'pickup_lng' => 1.22, 'is_active' => true]);
        $client->deliveries()->create([...$this->payload(['pickup_address' => 'Grand marché']), 'product_id' => $product->id, 'quantity' => 1, 'distance_km' => 3, 'delivery_fee' => 1000, 'total_amount' => 1000]);
        $this->actingAs($admin)->get(route('admin.requests.show', $request))->assertOk()->assertSee('Boutique Bè');

        $schedule = fn (array $o = []) => $this->actingAs($admin)->post(route('admin.requests.schedule', $request), [
            'type' => 'express', // toujours permis à l'agence
            'pickup_address' => 'Boutique', 'pickup_lat' => 6.13, 'pickup_lng' => 1.24,
            'dropoff_address' => 'Agoè', 'dropoff_lat' => 6.2, 'dropoff_lng' => 1.2,
            'recipient_name' => 'Ama', 'recipient_phone' => '+22891111111', 'delivery_fee' => 1500,
            ...$o,
        ]);

        $schedule(['scheduled_at' => now()->addHours(3)->format('Y-m-d H:i'), 'deadline_at' => now()->addHour()->format('Y-m-d H:i')])
            ->assertSessionHasErrors(['deadline_at' => "L'heure limite doit être après l'heure de passage programmée."]);
        $schedule()->assertSessionHasNoErrors();
        $first = $request->refresh()->delivery;
        $schedule()->assertSessionHasErrors('schedule'); // pas de double programmation
        $this->assertSame(1, Delivery::where('dropoff_address', 'Agoè')->count());

        // Montant à encaisser exposé au livreur.
        $courier = User::factory()->courier()->create();
        $this->post(route('admin.deliveries.confirm-payment', $first), ['method' => 'flooz']);
        $this->post(route('admin.deliveries.assign', $first), ['courier_id' => $courier->id]);
        $this->app['auth']->forgetGuards();
        Sanctum::actingAs($courier);
        $this->getJson('/api/v1/courier/deliveries')->assertJsonPath('data.0.parcel_amount', 12000);
        $this->app['auth']->forgetGuards();

        // Clôture refusée tant que la livraison est en cours.
        $this->actingAs($admin)->post(route('admin.requests.close', $request))->assertSessionHasErrors('close');
        $this->assertSame(DeliveryRequest::SCHEDULED, $request->refresh()->status);

        // Message du client sur une demande programmée : visible par l'agence.
        $this->app['auth']->forgetGuards();
        Sanctum::actingAs($client);
        $this->postJson("/api/v1/requests/{$request->id}/messages", ['body' => 'Changez l\'heure svp'])->assertCreated();
        $this->app['auth']->forgetGuards();
        $this->assertSame(1, RequestController::unreadCount());
        $this->actingAs($admin)->get(route('admin.requests.index'))->assertOk()->assertSee($client->name);

        // Livraison annulée : la demande se rouvre et peut être reprogrammée.
        $this->post(route('admin.deliveries.cancel', $first), ['reason' => 'Mauvaise adresse'])->assertSessionHasNoErrors();
        $this->assertSame(DeliveryRequest::OPEN, $request->refresh()->status);
        $this->get(route('admin.requests.show', $request))->assertOk()->assertSee('Reprogrammer la livraison');
        $schedule()->assertSessionHasNoErrors();
        $this->assertNotSame($first->id, $request->refresh()->delivery_id);
        $this->assertSame(DeliveryRequest::SCHEDULED, $request->status);
    }

    public function test_login_is_locked_per_account_after_five_failures(): void
    {
        $user = User::factory()->create(['phone_number' => '+22890112233', 'password' => 'password123']);
        $attempt = fn (string $login, string $password = 'mauvais') => $this->postJson('/api/v1/login', compact('login', 'password'));

        // Même compte sous plusieurs écritures : compté ensemble.
        foreach (['90112233', '+22890112233', '90 11 22 33', '22890112233', '0022890112233'] as $login) {
            $attempt($login)->assertUnprocessable();
        }
        $attempt('90112233', 'password123')->assertStatus(429)
            ->assertJsonPath('errors.login.0', fn ($m) => str_contains($m, 'Réessayez dans 15 minutes'));

        // Un autre compte n'est pas bloqué.
        $other = User::factory()->create(['password' => 'password123']);
        $attempt($other->phone_number, 'password123')->assertOk();

        $this->travel(16)->minutes();
        $attempt('90112233', 'password123')->assertOk()->assertJsonPath('user.id', $user->id);
    }

    public function test_courier_phone_is_normalized_unique_and_busy_courier_cannot_be_disabled(): void
    {
        $admin = User::factory()->admin()->create();
        User::factory()->create(['phone_number' => '90112233']); // ancien compte enregistré sans indicatif

        $form = fn (array $o = []) => [
            'name' => 'Kossi', 'phone_number' => '91 22 33 44', 'password' => 'password123',
            'password_confirmation' => 'password123', 'is_active' => '1', ...$o,
        ];

        $this->actingAs($admin)->post(route('admin.couriers.store'), $form(['phone_number' => '+228 90 11 22 33']))
            ->assertSessionHasErrors('phone_number');
        $this->post(route('admin.couriers.store'), $form())->assertSessionHasNoErrors();
        $courier = User::where('phone_number', '+22891223344')->firstOrFail();

        // Sa propre écriture reste acceptée à la modification.
        $this->put(route('admin.couriers.update', $courier), $form(['phone_number' => '91223344', 'password' => '', 'password_confirmation' => '']))
            ->assertSessionHasNoErrors();

        $d = $this->delivery(User::factory()->create());
        $this->actingAs($admin)->post(route('admin.deliveries.confirm-payment', $d), ['method' => 'flooz']);
        $this->post(route('admin.deliveries.assign', $d), ['courier_id' => $courier->id]);

        $this->put(route('admin.couriers.update', $courier), $form(['is_active' => null, 'password' => '', 'password_confirmation' => '']))
            ->assertSessionHasErrors('is_active');
        $this->assertTrue($courier->refresh()->is_active);
    }

    public function test_dashboard_revenue_counts_delivery_fees_delivered_this_month(): void
    {
        $admin = User::factory()->admin()->create();
        $client = User::factory()->create();
        $make = fn (array $attrs) => $client->deliveries()->create([...$this->payload(), 'distance_km' => 3, 'delivery_fee' => 1000, 'items_amount' => 5000, 'total_amount' => 6000])
            ->forceFill($attrs)->save();

        $make(['status' => 'delivered', 'payment_status' => 'verified', 'delivered_at' => now()]);
        $make(['status' => 'delivered', 'payment_status' => 'verified', 'delivered_at' => now()->subMonthNoOverflow()->startOfMonth()]);
        $make(['status' => 'assigned', 'payment_status' => 'verified']);
        $make(['status' => 'cancelled', 'payment_status' => 'verified']);

        $this->actingAs($admin)->get(route('admin.dashboard'))->assertOk()->assertViewHas('revenueMonth', 1000);
    }

    public function test_client_import_is_limited_to_300_rows(): void
    {
        $admin = User::factory()->admin()->create();
        $csv = "nom;téléphone\n".implode("\n", array_map(fn ($i) => "Client $i;9".str_pad((string) $i, 7, '0', STR_PAD_LEFT), range(1, 301)));
        $file = UploadedFile::fake()->createWithContent('clients.csv', $csv);

        $this->actingAs($admin)->post(route('admin.clients.import.store'), ['file' => $file])
            ->assertSessionHasErrors(['file' => 'Le fichier contient 301 lignes : 300 clients maximum par import. Découpez-le en plusieurs fichiers et importez-les un par un.']);
        $this->assertSame(1, User::count());
    }

    public function test_admin_search_treats_percent_and_underscore_literally(): void
    {
        $admin = User::factory()->admin()->create();
        $client = User::factory()->create(['name' => 'Afi_Mensah']);
        User::factory()->create(['name' => 'AfixMensah']);
        $d = $this->delivery($client);

        $this->actingAs($admin)->get(route('admin.clients.index', ['search' => 'Afi_']))
            ->assertOk()->assertSee('Afi_Mensah')->assertDontSee('AfixMensah');
        $this->get(route('admin.deliveries.index', ['search' => '%']))->assertOk()->assertDontSee($d->reference);
        $this->get(route('admin.deliveries.index', ['search' => $d->reference]))->assertOk()->assertSee($d->reference);
    }
}
