@extends('layouts.admin')

@section('title', 'Livreurs')

@section('content')
    <div class="flex items-center justify-between mb-4">
        <h1 class="text-2xl font-bold">Livreurs</h1>
        <a href="{{ route('admin.couriers.create') }}" class="bg-black text-brand font-semibold rounded px-4 py-2">+ Nouveau livreur</a>
    </div>

    <div class="bg-white rounded-lg shadow-sm overflow-x-auto">
        <table class="min-w-full text-sm">
            <thead class="bg-gray-50 text-left text-gray-500">
            <tr>
                <th class="px-4 py-2">Nom</th>
                <th class="px-4 py-2">Téléphone</th>
                <th class="px-4 py-2">Email</th>
                <th class="px-4 py-2">Véhicule</th>
                <th class="px-4 py-2 text-center">En cours</th>
                <th class="px-4 py-2 text-center">Livrées</th>
                <th class="px-4 py-2">Compte</th>
                <th class="px-4 py-2"></th>
            </tr>
            </thead>
            <tbody class="divide-y">
            @forelse ($couriers as $courier)
                <tr>
                    <td class="px-4 py-2 font-medium">{{ $courier->name }}</td>
                    <td class="px-4 py-2">{{ $courier->phone_number }}</td>
                    <td class="px-4 py-2">{{ $courier->email ?? '—' }}</td>
                    <td class="px-4 py-2">{{ $courier->vehicle ?? '—' }}</td>
                    <td class="px-4 py-2 text-center">{{ $courier->active_count }}</td>
                    <td class="px-4 py-2 text-center">{{ $courier->delivered_count }}</td>
                    <td class="px-4 py-2">
                        <span class="px-2 py-0.5 rounded-full text-xs {{ $courier->is_active ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800' }}">
                            {{ $courier->is_active ? 'Actif' : 'Désactivé' }}
                        </span>
                    </td>
                    <td class="px-4 py-2 text-right"><a class="text-blue-600 underline" href="{{ route('admin.couriers.edit', $courier) }}">Modifier</a></td>
                </tr>
            @empty
                <tr><td colspan="8" class="px-4 py-8 text-center text-gray-500">Aucun livreur. Créez le premier compte.</td></tr>
            @endforelse
            </tbody>
        </table>
    </div>
    <div class="mt-4">{{ $couriers->links() }}</div>
@endsection
