<?php

namespace App\Http\Controllers;

use App\Models\Setting;
use Illuminate\View\View;

/** Pages publiques exigées par Google Play : politique de confidentialité et suppression de compte. */
class LegalController extends Controller
{
    public function privacy(): View
    {
        return view('legal.privacy', $this->contact());
    }

    public function accountDeletion(): View
    {
        return view('legal.account-deletion', $this->contact());
    }

    /** @return array{supportPhone: ?string, supportEmail: ?string} */
    private function contact(): array
    {
        return [
            'supportPhone' => Setting::get('support_phone') ?: null,
            'supportEmail' => Setting::get('support_email') ?: null,
        ];
    }
}
