@extends('layouts.admin')

@section('title', $courier->exists ? 'Modifier le livreur' : 'Nouveau livreur')

@section('content')
    <a href="{{ route('admin.couriers.index') }}" class="text-gray-500">← Livreurs</a>
    <h1 class="text-2xl font-bold mt-2 mb-4">{{ $courier->exists ? 'Modifier '.$courier->name : 'Nouveau livreur' }}</h1>

    <form method="POST" action="{{ $courier->exists ? route('admin.couriers.update', $courier) : route('admin.couriers.store') }}"
          class="bg-white rounded-lg shadow-sm p-6 max-w-xl space-y-4">
        @csrf
        @if ($courier->exists) @method('PUT') @endif

        @foreach ([['name', 'Nom complet', 'text', true], ['phone_number', 'Téléphone (identifiant de connexion)', 'tel', true], ['email', 'Email (optionnel)', 'email', false], ['vehicle', 'Véhicule (ex. Moto Haojue · TG-1234-AB)', 'text', false]] as [$field, $label, $type, $required])
            <div>
                <label class="block text-sm font-medium mb-1" for="{{ $field }}">{{ $label }}</label>
                <input id="{{ $field }}" name="{{ $field }}" type="{{ $type }}" value="{{ old($field, $courier->$field) }}" @required($required)
                       class="w-full border rounded px-3 py-2">
            </div>
        @endforeach

        <div class="grid grid-cols-2 gap-4">
            <div>
                <label class="block text-sm font-medium mb-1" for="password">Mot de passe {{ $courier->exists ? '(laisser vide pour ne pas changer)' : '' }}</label>
                <input id="password" name="password" type="password" @required(! $courier->exists) class="w-full border rounded px-3 py-2">
            </div>
            <div>
                <label class="block text-sm font-medium mb-1" for="password_confirmation">Confirmation</label>
                <input id="password_confirmation" name="password_confirmation" type="password" class="w-full border rounded px-3 py-2">
            </div>
        </div>

        <label class="flex items-center gap-2">
            <input type="checkbox" name="is_active" value="1" @checked(old('is_active', $courier->is_active))>
            Compte actif (le livreur peut se connecter et recevoir des livraisons)
        </label>

        <button class="bg-black text-brand font-semibold rounded px-6 py-2">Enregistrer</button>
    </form>
@endsection
