<?php

namespace Tests\Feature;

use App\Models\DeliveryRequest;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class RequestChatProfileTest extends TestCase
{
    use RefreshDatabase;

    private function photo(string $name = 'article.jpg'): UploadedFile
    {
        return UploadedFile::fake()->image($name, 400, 300);
    }

    public function test_user_can_set_change_and_remove_profile_photo(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $first = $this->post('/api/v1/me/avatar', ['photo' => $this->photo()], ['Accept' => 'application/json'])
            ->assertOk()->json('data.avatar_url');
        $this->assertNotNull($first);

        $second = $this->post('/api/v1/me/avatar', ['photo' => $this->photo('new.png')], ['Accept' => 'application/json'])
            ->assertOk()->json('data.avatar_url');
        $this->assertNotSame($first, $second);
        $this->assertDatabaseCount('media', 1); // l'ancienne photo est supprimée

        $this->get($second)->assertOk()->assertHeader('Content-Type', 'image/png');

        $this->deleteJson('/api/v1/me/avatar')->assertOk()->assertJsonPath('data.avatar_url', null);
        $this->assertDatabaseCount('media', 0);
    }

    public function test_any_client_can_use_photo_programming(): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->post('/api/v1/requests', ['photos' => [$this->photo()]], ['Accept' => 'application/json'])
            ->assertCreated();
        $this->assertDatabaseCount('delivery_requests', 1);
    }

    public function test_client_sends_photos_chats_and_admin_schedules_delivery(): void
    {
        $client = User::factory()->create();
        $admin = User::factory()->admin()->create();

        // 1. Le client envoie ses articles en photos.
        Sanctum::actingAs($client);
        $res = $this->post('/api/v1/requests', [
            'photos' => [$this->photo('robe.jpg'), $this->photo('sac.jpg')],
            'message' => 'À livrer demain matin',
        ], ['Accept' => 'application/json'])->assertCreated();
        $requestId = $res->json('data.id');
        $this->assertCount(4, $res->json('data.messages')); // 2 photos + texte + accusé de réception

        // 2. Il partage la position de livraison dans la discussion.
        $this->postJson("/api/v1/requests/{$requestId}/messages", ['lat' => 6.2, 'lng' => 1.2])
            ->assertCreated()->assertJsonPath('data.from', 'client');
        $this->app['auth']->forgetGuards();

        // 3. L'agence répond puis programme la livraison.
        $this->actingAs($admin)->get('/admin/requests')->assertOk()->assertSee($client->name);
        $this->get('/admin/clients')->assertOk()->assertDontSee('Habitué');
        $this->get("/admin/requests/{$requestId}")->assertOk()->assertSee('Programmer la livraison');
        $this->post("/admin/requests/{$requestId}/reply", ['body' => 'Ok, 1 500 FCFA'])->assertRedirect();
        $this->post("/admin/requests/{$requestId}/schedule", [
            'type' => 'colis',
            'pickup_address' => 'Boutique Bè', 'pickup_lat' => 6.1375, 'pickup_lng' => 1.24,
            'dropoff_address' => 'Agoè', 'dropoff_lat' => 6.2, 'dropoff_lng' => 1.2,
            'recipient_name' => 'Ama', 'recipient_phone' => '+22891111111',
            'delivery_fee' => 1500,
            'parcel_amount' => 15000, // saisi par l'admin
        ])->assertRedirect()->assertSessionHasNoErrors();

        $request = DeliveryRequest::findOrFail($requestId);
        $this->assertSame(DeliveryRequest::SCHEDULED, $request->status);
        $delivery = $request->delivery;
        $this->assertSame(1500, $delivery->total_amount);
        $this->assertStringContainsString('Montant total du colis : 15 000 FCFA', $delivery->notes);
        $this->assertSame(15000, $request->parcel_amount);
        $this->assertSame('Agoè', $request->district);
        $this->assertSame($client->id, $delivery->client_id);
        $this->assertCount(2, $delivery->photos);
        $this->get(route('admin.deliveries.show', $delivery))->assertOk()->assertSee('Photos des articles');
        $this->app['auth']->forgetGuards();

        // 4. Le client voit la réponse, la livraison programmée et peut payer.
        Sanctum::actingAs($client);
        $this->getJson('/api/v1/requests')->assertOk()->assertJsonPath('data.0.unread', 2);
        $this->getJson("/api/v1/requests/{$requestId}")
            ->assertOk()
            ->assertJsonPath('data.delivery.reference', $delivery->reference)
            ->assertJsonPath('data.delivery.can_pay', true);
        $this->getJson("/api/v1/deliveries/{$delivery->id}")
            ->assertOk()
            ->assertJsonCount(2, 'data.photos')
            ->assertJsonPath('data.request_id', $requestId);
    }

    public function test_photo_programming_needs_only_a_photo(): void
    {
        Sanctum::actingAs(User::factory()->create());
        $headers = ['Accept' => 'application/json'];

        // Sans photo : refusé.
        $this->post('/api/v1/requests', [], $headers)->assertUnprocessable()->assertJsonValidationErrors('photos');
        $this->assertDatabaseCount('delivery_requests', 0);

        // Une photo seule suffit (commerçants qui ne savent pas écrire) : l'admin complète le reste.
        $this->post('/api/v1/requests', ['photos' => [$this->photo()]], $headers)
            ->assertCreated()
            ->assertJsonPath('data.district', null)
            ->assertJsonPath('data.parcel_amount', null);
    }

    public function test_client_cannot_read_another_clients_request(): void
    {
        $owner = User::factory()->create();
        $request = $owner->deliveryRequests()->create();

        Sanctum::actingAs(User::factory()->create());
        $this->getJson("/api/v1/requests/{$request->id}")->assertNotFound();
        $this->postJson("/api/v1/requests/{$request->id}/messages", ['body' => 'Salut'])->assertNotFound();
    }

    public function test_new_client_can_attach_photos_to_a_regular_delivery(): void
    {
        Sanctum::actingAs(User::factory()->create());
        $id = $this->postJson('/api/v1/deliveries', [
            'type' => 'colis',
            'pickup_address' => 'Bè', 'pickup_lat' => 6.1375, 'pickup_lng' => 1.24,
            'dropoff_address' => 'Kégué', 'dropoff_lat' => 6.165, 'dropoff_lng' => 1.26,
            'recipient_name' => 'Yao', 'recipient_phone' => '+22893000000',
        ])->assertCreated()->json('data.id');

        $this->post("/api/v1/deliveries/{$id}/photos", ['photo' => $this->photo()], ['Accept' => 'application/json'])
            ->assertOk()
            ->assertJsonCount(1, 'data.photos');
    }
}
