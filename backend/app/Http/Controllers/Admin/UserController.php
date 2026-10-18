<?php

namespace App\Http\Controllers\Admin;

use App\Enums\DeliveryStatus;
use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Models\User;
use App\Support\Phone;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use App\Support\Identifier;
use Illuminate\Validation\Rules\Password;
use Illuminate\Validation\ValidationException;
use Illuminate\View\View;

/** Gestion des comptes livreurs (créés uniquement par l'admin) et consultation des clients. */
class UserController extends Controller
{
    public function couriers(): View
    {
        $couriers = User::couriers()
            ->withCount([
                'assignedDeliveries as active_count' => fn ($q) => $q
                    ->whereIn('status', [DeliveryStatus::Assigned, DeliveryStatus::PickedUp]),
                'assignedDeliveries as delivered_count' => fn ($q) => $q
                    ->where('status', DeliveryStatus::Delivered),
            ])
            ->orderByDesc('is_active')
            ->orderBy('name')
            ->paginate(25);

        return view('admin.couriers.index', compact('couriers'));
    }

    public function create(): View
    {
        return view('admin.couriers.form', ['courier' => new User(['is_active' => true])]);
    }

    public function store(Request $request): RedirectResponse
    {
        $data = $this->validated($request);

        User::create([...$data, 'role' => Role::Courier]);

        return redirect()->route('admin.couriers.index')->with('success', 'Compte livreur créé.');
    }

    public function edit(User $courier): View
    {
        abort_unless($courier->isCourier() && ! $courier->isAnonymized(), 404);

        return view('admin.couriers.form', compact('courier'));
    }

    public function update(Request $request, User $courier): RedirectResponse
    {
        abort_unless($courier->isCourier() && ! $courier->isAnonymized(), 404);

        $data = $this->validated($request, $courier);
        if (empty($data['password'])) {
            unset($data['password']);
        }

        // Pas de désactivation tant que des colis sont entre ses mains : ils seraient bloqués.
        if ($courier->is_active && ! $data['is_active']) {
            $active = $courier->assignedDeliveries()
                ->whereIn('status', [DeliveryStatus::Assigned, DeliveryStatus::PickedUp])->count();
            if ($active > 0) {
                throw ValidationException::withMessages([
                    'is_active' => "Ce livreur a {$active} course(s) en cours : réassignez-les à un autre livreur (ou attendez la livraison) avant de le désactiver.",
                ]);
            }
        }

        $courier->update($data);

        if (! $courier->is_active) {
            // Déconnecte immédiatement l'application du livreur désactivé.
            $courier->tokens()->delete();
        }

        return redirect()->route('admin.couriers.index')->with('success', 'Compte livreur mis à jour.');
    }

    public function clients(Request $request): View
    {
        $search = $request->string('search')->trim()->toString();

        $clients = User::query()
            ->where('role', Role::Client)
            ->when($search, function ($q) use ($search) {
                // Insensible à la casse ; % et _ tapés par l'admin sont cherchés tels quels, pas comme jokers.
                $q->where(fn ($q) => $q
                    ->whereContains('name', $search)
                    ->orWhereContains('phone_number', $search)
                    ->orWhereContains('email', $search));
            })
            ->withCount('deliveries')
            ->with('avatar:id,uuid')
            ->latest()
            ->paginate(25)
            ->withQueryString();

        return view('admin.clients.index', compact('clients', 'search'));
    }

    public function toggleClient(User $client): RedirectResponse
    {
        abort_unless($client->isClient(), 404);
        if ($client->isAnonymized()) {
            return back()->withErrors(['client' => 'Ce compte a été supprimé par son titulaire : il ne peut pas être réactivé.']);
        }

        $client->update(['is_active' => ! $client->is_active]);
        if (! $client->is_active) {
            $client->tokens()->delete();
        }

        return back()->with('success', $client->is_active ? 'Client réactivé.' : 'Client désactivé.');
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, ?User $courier = null): array
    {
        // Email enregistré en minuscules : unicité et connexion insensibles à la casse.
        if (is_string($request->input('email'))) {
            $request->merge(['email' => Identifier::email($request->input('email'))]);
        }
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['nullable', 'email', 'max:255', Identifier::uniqueEmail($courier?->id)],
            'phone_number' => ['required', 'string', 'max:30'],
            'vehicle' => ['nullable', 'string', 'max:255'],
            'password' => [$courier ? 'nullable' : 'required', 'confirmed', Password::min(8)],
        ]);

        // Une seule écriture du numéro (identifiant de connexion), unique sous toutes ses formes.
        $data['phone_number'] = Phone::normalize($data['phone_number']);
        $taken = User::whereIn('phone_number', Phone::variants($data['phone_number']))
            ->when($courier, fn ($q) => $q->whereKeyNot($courier->id))
            ->exists();
        if ($taken) {
            throw ValidationException::withMessages(['phone_number' => 'Ce numéro est déjà utilisé par un autre compte.']);
        }

        return [...$data, 'is_active' => $request->boolean('is_active')];
    }
}
