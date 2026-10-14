<?php

namespace App\Http\Controllers\Admin;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Models\User;
use App\Support\Phone;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Validation\ValidationException;
use Illuminate\View\View;

/**
 * Comptes des anciens clients de l'agence, créés depuis le panneau admin :
 * l'agence leur transmet leurs identifiants (numéro + mot de passe), modifiables ensuite dans l'app.
 */
class ClientAccountController extends Controller
{
    /** Au-delà, la requête dépasse le délai de Render (un mot de passe haché par client). */
    private const MAX_IMPORT_ROWS = 300;

    public function create(): View
    {
        return view('admin.clients.create');
    }

    public function store(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'phone_number' => ['required', 'string', 'max:30'],
            'district' => ['nullable', 'string', 'max:120'],
            'email' => ['nullable', 'email', 'max:255', 'unique:users,email'],
        ]);

        if (! Phone::isValid($data['phone_number'])) {
            throw ValidationException::withMessages(['phone_number' => 'Numéro invalide (8 chiffres attendus).']);
        }
        $phone = Phone::normalize($data['phone_number']);
        if ($this->phoneTaken($phone)) {
            throw ValidationException::withMessages(['phone_number' => 'Ce numéro a déjà un compte.']);
        }

        $password = $this->generatePassword();
        $this->createClient($data['name'], $phone, $data['district'] ?? null, $data['email'] ?? null, $password);

        return redirect()->route('admin.clients.credentials')->with('credentials', [
            ['name' => $data['name'], 'phone' => $phone, 'password' => $password],
        ]);
    }

    public function importForm(): View
    {
        return view('admin.clients.import');
    }

    /** Import CSV (Excel : « Enregistrer sous » › CSV UTF-8 ou CSV séparateur point-virgule). */
    public function import(Request $request): RedirectResponse
    {
        $request->validate(['file' => ['required', 'file', 'max:2048']]);

        $rows = $this->readCsv($request->file('file'));
        if ($rows === []) {
            throw ValidationException::withMessages(['file' => 'Fichier vide ou illisible. Colonnes attendues : nom ; téléphone ; quartier.']);
        }

        if (count($rows) > self::MAX_IMPORT_ROWS) {
            throw ValidationException::withMessages(['file' => 'Le fichier contient '.count($rows).' lignes : '
                .self::MAX_IMPORT_ROWS.' clients maximum par import. Découpez-le en plusieurs fichiers et importez-les un par un.']);
        }

        $existing = User::pluck('phone_number')->map(fn ($p) => Phone::normalize((string) $p))->flip();
        $created = [];
        $skipped = [];

        foreach ($rows as $line => $row) {
            $name = trim($row['name']);
            $raw = trim($row['phone']);
            $label = $name !== '' ? $name : "Ligne $line";

            if ($name === '' || $raw === '') {
                $skipped[] = ['row' => $label, 'phone' => $raw, 'reason' => 'Nom ou téléphone manquant'];
                continue;
            }
            if (! Phone::isValid($raw)) {
                $skipped[] = ['row' => $label, 'phone' => $raw, 'reason' => 'Numéro invalide'];
                continue;
            }
            $phone = Phone::normalize($raw);
            if ($existing->has($phone)) {
                $skipped[] = ['row' => $label, 'phone' => $phone, 'reason' => 'Déjà client (ou en double dans le fichier)'];
                continue;
            }

            $password = $this->generatePassword();
            $this->createClient($name, $phone, trim($row['district']) ?: null, null, $password);
            $existing->put($phone, true);
            $created[] = ['name' => $name, 'phone' => $phone, 'password' => $password];
        }

        return redirect()->route('admin.clients.credentials')
            ->with('credentials', $created)
            ->with('skipped', $skipped);
    }

    /** Nouveau mot de passe (client qui a oublié le sien) : les sessions ouvertes sont fermées. */
    public function resetPassword(User $client): RedirectResponse
    {
        abort_unless($client->isClient(), 404);

        $password = $this->generatePassword();
        $client->forceFill(['password' => $password])->save();
        $client->tokens()->delete();

        return redirect()->route('admin.clients.credentials')->with('credentials', [
            ['name' => $client->name, 'phone' => $client->phone_number, 'password' => $password],
        ]);
    }

    /** Identifiants à transmettre : affichés une seule fois (jamais stockés en clair). */
    public function credentials(Request $request): View|RedirectResponse
    {
        $credentials = $request->session()->get('credentials');
        if ($credentials === null) {
            return redirect()->route('admin.clients.index');
        }

        $apkUrl = config('services.apk.url');
        $credentials = array_map(function (array $c) use ($apkUrl) {
            $message = "Bonjour {$c['name']}, votre compte VOOM Delivery est prêt.\n"
                ."Téléchargez l'application : $apkUrl\n"
                ."Identifiant : {$c['phone']}\nMot de passe : {$c['password']}\n"
                .'Vous pourrez le changer dans Profil › Mes identifiants.';

            return [...$c, 'message' => $message, 'whatsapp' => Phone::whatsappLink($c['phone'], $message)];
        }, $credentials);

        return view('admin.clients.credentials', [
            'credentials' => $credentials,
            'skipped' => $request->session()->get('skipped', []),
        ]);
    }

    private function createClient(string $name, string $phone, ?string $district, ?string $email, string $password): User
    {
        return User::create([
            'name' => $name,
            'phone_number' => $phone,
            'district' => $district,
            'email' => $email,
            'password' => $password,
            'role' => Role::Client,
            'is_active' => true,
        ]);
    }

    private function phoneTaken(string $normalized): bool
    {
        return User::whereIn('phone_number', Phone::variants($normalized))->exists();
    }

    /** 8 chiffres : facile à taper sur un clavier de téléphone, à changer ensuite dans l'app. */
    private function generatePassword(): string
    {
        return str_pad((string) random_int(0, 99_999_999), 8, '0', STR_PAD_LEFT);
    }

    /**
     * Lit un CSV Excel (séparateur ; , ou tabulation, UTF-8 ou Windows-1252, en-tête facultatif).
     *
     * @return array<int, array{name: string, phone: string, district: string}> indexé par numéro de ligne
     */
    private function readCsv(UploadedFile $file): array
    {
        $content = (string) file_get_contents($file->getRealPath());
        $content = preg_replace('/^\xEF\xBB\xBF/', '', $content) ?? '';
        if (! mb_check_encoding($content, 'UTF-8')) {
            $content = mb_convert_encoding($content, 'UTF-8', 'Windows-1252');
        }

        $lines = preg_split('/\r\n|\r|\n/', trim($content)) ?: [];
        if ($lines === [] || trim($lines[0]) === '') {
            return [];
        }
        $first = $lines[0];
        $delimiter = collect([';', ',', "\t"])->sortByDesc(fn ($d) => substr_count($first, $d))->first();

        // En-tête reconnu par ses libellés, sinon ordre nom ; téléphone ; quartier.
        $columns = ['name' => 0, 'phone' => 1, 'district' => 2];
        $header = array_map(fn ($h) => mb_strtolower(trim($h)), str_getcsv($first, $delimiter));
        $start = 0;
        if (array_filter($header, fn ($h) => preg_match('/nom|name|t[ée]l|phone|num[ée]ro/u', $h))) {
            $start = 1;
            foreach ($header as $i => $h) {
                if (preg_match('/t[ée]l|phone|num[ée]ro|contact/u', $h)) {
                    $columns['phone'] = $i;
                } elseif (preg_match('/quartier|district|zone|adresse/u', $h)) {
                    $columns['district'] = $i;
                } elseif (preg_match('/nom|name|client/u', $h)) {
                    $columns['name'] = $i;
                }
            }
        }

        $rows = [];
        foreach (array_slice($lines, $start, null, true) as $index => $line) {
            if (trim($line) === '') {
                continue;
            }
            $cells = str_getcsv($line, $delimiter);
            $rows[$index + 1] = [
                'name' => (string) ($cells[$columns['name']] ?? ''),
                'phone' => (string) ($cells[$columns['phone']] ?? ''),
                'district' => (string) ($cells[$columns['district']] ?? ''),
            ];
        }

        return $rows;
    }
}
