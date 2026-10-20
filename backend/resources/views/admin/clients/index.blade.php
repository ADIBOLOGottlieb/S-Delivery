@extends('layouts.admin')

@section('title', 'Clients')

@section('content')
    <div class="flex flex-wrap items-center justify-between gap-3 mb-4">
        <h1 class="text-2xl font-bold">Clients</h1>
        <div class="flex flex-wrap gap-2">
            <form method="GET" class="flex gap-2">
                <input name="search" value="{{ $search }}" placeholder="Nom, téléphone, email" class="border rounded px-3 py-2 w-56">
                <button class="border border-black rounded px-4 py-2 font-semibold">Rechercher</button>
            </form>
            <a href="{{ route('admin.clients.import') }}" class="border border-black bg-white rounded px-4 py-2 font-semibold">Importer (CSV)</a>
            <a href="{{ route('admin.clients.create') }}" class="bg-black text-brand rounded px-4 py-2 font-semibold">+ Ajouter un client</a>
        </div>
    </div>

    <div class="bg-white rounded-lg shadow-sm overflow-x-auto">
        <table class="min-w-full text-sm">
            <thead class="bg-gray-50 text-left text-gray-500">
            <tr>
                <th class="px-4 py-2">Nom</th>
                <th class="px-4 py-2">Téléphone</th>
                <th class="px-4 py-2">Email</th>
                <th class="px-4 py-2 text-center">Livraisons</th>
                <th class="px-4 py-2">Inscrit le</th>
                <th class="px-4 py-2"></th>
            </tr>
            </thead>
            <tbody class="divide-y">
            @forelse ($clients as $client)
                <tr>
                    <td class="px-4 py-2 font-medium">
                        <div class="flex items-center gap-2">
                            @if ($client->avatar)
                                <img src="{{ $client->avatar->url() }}" alt="" class="w-8 h-8 rounded-full object-cover">
                            @else
                                <span class="w-8 h-8 rounded-full bg-black text-brand flex items-center justify-center text-xs font-bold">{{ mb_strtoupper(mb_substr($client->name, 0, 1)) }}</span>
                            @endif
                            {{ $client->name }}
                        </div>
                    </td>
                    <td class="px-4 py-2">{{ $client->phone_number }}@if ($client->district)<div class="text-xs text-gray-500">{{ $client->district }}</div>@endif</td>
                    <td class="px-4 py-2">{{ $client->email ?? '—' }}</td>
                    <td class="px-4 py-2 text-center">
                        <a class="text-blue-600 underline" href="{{ route('admin.deliveries.index', ['search' => $client->phone_number]) }}">{{ $client->deliveries_count }}</a>
                    </td>
                    <td class="px-4 py-2">{{ $client->created_at->format('d/m/Y') }}</td>
                    <td class="px-4 py-2 text-right whitespace-nowrap">
                        <form method="POST" action="{{ route('admin.clients.password', $client) }}" class="inline"
                              onsubmit="return confirm({{ Js::from('Générer un nouveau mot de passe pour '.$client->name." ? L'ancien ne fonctionnera plus.") }})">
                            @csrf
                            <button class="text-sm text-blue-700 underline mr-3">Nouveau mot de passe</button>
                        </form>
                        <form method="POST" action="{{ route('admin.clients.toggle', $client) }}" class="inline">
                            @csrf
                            <button class="text-sm {{ $client->is_active ? 'text-red-700' : 'text-green-700' }} underline">
                                {{ $client->is_active ? 'Désactiver' : 'Réactiver' }}
                            </button>
                        </form>
                    </td>
                </tr>
            @empty
                <tr><td colspan="7" class="px-4 py-8 text-center text-gray-500">Aucun client.</td></tr>
            @endforelse
            </tbody>
        </table>
    </div>
    <div class="mt-4">{{ $clients->links() }}</div>
@endsection
