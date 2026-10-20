@extends('layouts.admin')

@section('title', 'Ajouter un client')

@section('content')
    <a href="{{ route('admin.clients.index') }}" class="text-gray-500">← Clients</a>
    <h1 class="text-2xl font-bold mt-2 mb-1">Ajouter un ancien client</h1>
    <p class="text-sm text-gray-600 mb-4 max-w-xl">
        Un mot de passe est généré :
        vous le transmettrez au client (WhatsApp en un clic à l'étape suivante). Il pourra le changer dans l'app.
    </p>

    <form method="POST" action="{{ route('admin.clients.store') }}" class="bg-white rounded-lg shadow-sm p-6 max-w-xl space-y-4">
        @csrf
        <div>
            <label class="block text-sm font-medium mb-1">Nom complet</label>
            <input name="name" value="{{ old('name') }}" required class="w-full border rounded px-3 py-2">
        </div>
        <div>
            <label class="block text-sm font-medium mb-1">Téléphone (identifiant de connexion)</label>
            <input name="phone_number" value="{{ old('phone_number') }}" required placeholder="90 11 22 33" class="w-full border rounded px-3 py-2">
        </div>
        <div class="grid grid-cols-2 gap-4">
            <div>
                <label class="block text-sm font-medium mb-1">Quartier <span class="text-gray-400">(facultatif)</span></label>
                <input name="district" value="{{ old('district') }}" class="w-full border rounded px-3 py-2">
            </div>
            <div>
                <label class="block text-sm font-medium mb-1">Email <span class="text-gray-400">(facultatif)</span></label>
                <input name="email" type="email" value="{{ old('email') }}" class="w-full border rounded px-3 py-2">
            </div>
        </div>
        <button class="bg-black text-brand font-semibold rounded px-6 py-2">Créer le compte</button>
    </form>
@endsection
