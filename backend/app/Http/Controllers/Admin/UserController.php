<?php

namespace App\Http\Controllers\Admin;

use App\Enums\DeliveryStatus;
use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;
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
        abort_unless($courier->isCourier(), 404);

        return view('admin.couriers.form', compact('courier'));
    }

    public function update(Request $request, User $courier): RedirectResponse
    {
        abort_unless($courier->isCourier(), 404);

        $data = $this->validated($request, $courier);
        if (empty($data['password'])) {
            unset($data['password']);
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
            ->when($search, fn ($q) => $q->where(fn ($q) => $q
                ->where('name', 'like', "%{$search}%")
                ->orWhere('phone_number', 'like', "%{$search}%")
                ->orWhere('email', 'like', "%{$search}%")))
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

        $client->update(['is_active' => ! $client->is_active]);
        if (! $client->is_active) {
            $client->tokens()->delete();
        }

        return back()->with('success', $client->is_active ? 'Client réactivé.' : 'Client désactivé.');
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, ?User $courier = null): array
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['nullable', 'email', 'max:255', Rule::unique('users')->ignore($courier)],
            'phone_number' => ['required', 'string', 'max:30', Rule::unique('users')->ignore($courier)],
            'vehicle' => ['nullable', 'string', 'max:255'],
            'password' => [$courier ? 'nullable' : 'required', 'confirmed', Password::min(8)],
        ]);

        return [...$data, 'is_active' => $request->boolean('is_active')];
    }
}
