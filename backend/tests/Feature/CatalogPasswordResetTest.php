<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\Setting;
use App\Models\Subcategory;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CatalogPasswordResetTest extends TestCase
{
    use RefreshDatabase;

    private function product(array $attributes = []): Product
    {
        return Product::create([
            'category' => 'agro', 'type' => 'product', 'name' => 'Riz', 'price' => 700, 'is_active' => true,
            'pickup_address' => 'Marché', 'pickup_lat' => 6.1, 'pickup_lng' => 1.2, ...$attributes,
        ]);
    }

    public function test_products_without_family_are_listed_under_autres_produits(): void
    {
        $sub = Subcategory::create(['category' => 'agro', 'name' => 'Céréales', 'position' => 0]);
        $this->product(['name' => 'Riz', 'subcategory_id' => $sub->id]);
        $this->product(['name' => 'Œufs']);
        Sanctum::actingAs(User::factory()->create());

        $this->getJson('/api/v1/subcategories?category=agro')->assertJsonPath('has_others', true);
        $this->getJson('/api/v1/products?category=agro&others=1')
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.name', 'Œufs');

        $admin = User::factory()->admin()->create();
        $this->actingAs($admin)->get('/admin/products?subcategory=others')
            ->assertOk()->assertSee('Autres produits')->assertSee('Œufs');
    }

    public function test_admin_uploads_are_stored_in_database_with_vendor_phone(): void
    {
        $this->actingAs(User::factory()->admin()->create())->post('/admin/products', [
            'type' => 'product', 'category' => 'agro', 'name' => 'Œufs', 'price' => 1500,
            'vendor_name' => 'Mama Afi', 'vendor_phone' => '90 11 22 33',
            'pickup_address' => 'Marché de Bè', 'pickup_lat' => 6.13, 'pickup_lng' => 1.24, 'is_active' => '1',
            'image' => UploadedFile::fake()->image('oeufs.jpg'),
        ])->assertRedirect()->assertSessionHasNoErrors();

        $product = Product::where('name', 'Œufs')->firstOrFail();
        $this->assertSame('+22890112233', $product->vendor_phone);
        $this->assertNull($product->subcategory_id); // « Autres produits »
        $this->assertStringStartsWith('media/', $product->image_path);
        $this->assertDatabaseCount('media', 1);
        $this->get($product->imageUrl())->assertOk();
    }

    public function test_payment_info_exposes_agency_phone(): void
    {
        Setting::put(['support_phone' => '+22891234567']);
        Sanctum::actingAs(User::factory()->create());

        $this->getJson('/api/v1/payment-info')->assertJsonPath('support_phone', '+22891234567');
    }

    public function test_client_resets_forgotten_password_with_emailed_code(): void
    {
        $user = User::factory()->create(['phone_number' => '+22890112233', 'email' => 'ama@example.com']);
        $user->createToken('mobile');

        $this->postJson('/api/v1/password/forgot', ['login' => '90 11 22 33'])
            ->assertOk()
            ->assertJsonPath('email', 'a***@example.com');

        $mail = collect(app('mailer')->getSymfonyTransport()->messages())->last();
        $this->assertNotNull($mail);
        preg_match('/(\d{6})/', $mail->getOriginalMessage()->getTextBody(), $m);
        $code = $m[1];

        // Mauvais code : refusé.
        $this->postJson('/api/v1/password/reset', [
            'login' => '90112233', 'code' => $code === '000000' ? '111111' : '000000',
            'password' => 'nouveau-mdp', 'password_confirmation' => 'nouveau-mdp',
        ])->assertUnprocessable()->assertJsonValidationErrors('code');

        $this->postJson('/api/v1/password/reset', [
            'login' => '90112233', 'code' => $code,
            'password' => 'nouveau-mdp', 'password_confirmation' => 'nouveau-mdp',
        ])->assertOk()->assertJsonStructure(['token', 'user']);

        $this->assertSame(1, $user->tokens()->count()); // anciens appareils déconnectés, nouveau jeton
        $this->postJson('/api/v1/login', ['login' => '90112233', 'password' => 'nouveau-mdp'])->assertOk();

        // Le code ne sert qu'une fois.
        $this->postJson('/api/v1/password/reset', [
            'login' => '90112233', 'code' => $code,
            'password' => 'encore-autre', 'password_confirmation' => 'encore-autre',
        ])->assertUnprocessable();
    }

    public function test_account_without_email_is_told_to_contact_the_agency(): void
    {
        User::factory()->create(['phone_number' => '+22890112233', 'email' => null]);

        $this->postJson('/api/v1/password/forgot', ['login' => '90112233'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('login');
        $this->assertDatabaseCount('password_reset_tokens', 0);
    }

    public function test_validation_messages_are_in_french(): void
    {
        $this->postJson('/api/v1/login', [])
            ->assertUnprocessable()
            ->assertJsonPath('errors.login.0', 'Le champ identifiant est obligatoire.');
    }
}
