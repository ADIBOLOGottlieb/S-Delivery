@extends('layouts.admin')

@section('title', 'Identifiants clients')

@section('content')
    <a href="{{ route('admin.clients.index') }}" class="text-gray-500">← Clients</a>
    <div class="flex flex-wrap items-end justify-between gap-3 mt-2 mb-4">
        <div>
            <h1 class="text-2xl font-bold">Identifiants à transmettre</h1>
            <p class="text-sm text-red-700 font-semibold">
                Affichés une seule fois : envoyez-les maintenant ou téléchargez la liste.
                (Mot de passe perdu ? Clients › « Nouveau mot de passe ».)
            </p>
        </div>
        @if (count($credentials) > 0)
            <button type="button" onclick="downloadCredentials()" class="bg-black text-brand font-semibold rounded px-4 py-2">
                Télécharger la liste (CSV)
            </button>
        @endif
    </div>

    <div class="bg-white rounded-lg shadow-sm overflow-x-auto">
        <table class="min-w-full text-sm">
            <thead class="bg-gray-50 text-left text-gray-500">
            <tr>
                <th class="px-4 py-2">Client</th>
                <th class="px-4 py-2">Identifiant (téléphone)</th>
                <th class="px-4 py-2">Mot de passe</th>
                <th class="px-4 py-2"></th>
            </tr>
            </thead>
            <tbody class="divide-y">
            @forelse ($credentials as $c)
                <tr>
                    <td class="px-4 py-2 font-medium">{{ $c['name'] }}</td>
                    <td class="px-4 py-2 font-mono">{{ $c['phone'] }}</td>
                    <td class="px-4 py-2 font-mono text-lg font-bold tracking-widest">{{ $c['password'] }}</td>
                    <td class="px-4 py-2 text-right whitespace-nowrap">
                        <a href="{{ $c['whatsapp'] }}" target="_blank" rel="noopener"
                           class="inline-block bg-green-600 text-white font-semibold rounded px-3 py-1.5">Envoyer par WhatsApp</a>
                        <button type="button" class="ml-2 underline text-gray-600"
                                onclick="navigator.clipboard.writeText(@js($c['message'])); this.textContent = 'Copié ✔'">Copier le message</button>
                    </td>
                </tr>
            @empty
                <tr><td colspan="4" class="px-4 py-8 text-center text-gray-500">Aucun compte créé.</td></tr>
            @endforelse
            </tbody>
        </table>
    </div>

    @if (count($skipped) > 0)
        <section class="bg-white rounded-lg shadow-sm p-5 mt-6">
            <h2 class="font-semibold mb-2">Lignes ignorées ({{ count($skipped) }})</h2>
            <ul class="text-sm text-gray-700 space-y-1">
                @foreach ($skipped as $s)
                    <li><strong>{{ $s['row'] }}</strong> {{ $s['phone'] ? '· '.$s['phone'] : '' }} — {{ $s['reason'] }}</li>
                @endforeach
            </ul>
        </section>
    @endif
@endsection

@push('scripts')
    <script>
        // Liste générée dans le navigateur : les mots de passe ne sont jamais conservés sur le serveur.
        function downloadCredentials() {
            const rows = @js(array_map(fn ($c) => [$c['name'], $c['phone'], $c['password']], $credentials));
            const csv = ['Nom;Identifiant;Mot de passe', ...rows.map(r => r.map(v => `"${String(v).replace(/"/g, '""')}"`).join(';'))].join('\r\n');
            const link = document.createElement('a');
            link.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' }));
            link.download = 'identifiants-clients-sdelivery.csv';
            link.click();
        }
    </script>
@endpush
