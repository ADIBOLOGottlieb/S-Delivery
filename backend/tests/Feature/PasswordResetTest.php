<?php

namespace Tests\Feature;

use App\Models\Setting;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class PasswordResetTest extends TestCase
{
    use RefreshDatabase;

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
