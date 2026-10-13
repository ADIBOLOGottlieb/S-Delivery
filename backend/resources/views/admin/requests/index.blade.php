@extends('layouts.admin')

@section('title', 'Demandes')

@section('content')
    @php
        $tabs = ['open' => 'En discussion', 'scheduled' => 'Programmées', 'closed' => 'Clôturées', 'all' => 'Toutes'];
    @endphp

    <div class="flex flex-wrap items-center justify-between gap-3 mb-4">
        <div>
            <h1 class="text-2xl font-bold">Demandes rapides</h1>
            <p class="text-sm text-gray-500">Programmation par photo : photos des articles + discussion. Programmez la livraison depuis la discussion.</p>
        </div>
        <nav class="flex gap-1 text-sm bg-white rounded-lg shadow-sm p-1">
            @foreach ($tabs as $key => $label)
                <a href="{{ route('admin.requests.index', ['status' => $key]) }}"
                   class="px-3 py-1.5 rounded {{ $status === $key ? 'bg-black text-voom font-semibold' : 'text-gray-600 hover:bg-gray-100' }}">{{ $label }}</a>
            @endforeach
        </nav>
    </div>

    <div class="bg-white rounded-lg shadow-sm divide-y">
        @forelse ($requests as $req)
            @php($unread = $req->hasUnreadForAdmin())
            <a href="{{ route('admin.requests.show', $req) }}" class="flex items-center gap-4 px-4 py-3 hover:bg-gray-50">
                <span class="w-10 h-10 rounded-full bg-black text-voom flex items-center justify-center font-bold shrink-0">
                    {{ mb_strtoupper(mb_substr($req->client->name, 0, 1)) }}
                </span>
                <div class="min-w-0 flex-1">
                    <div class="flex items-center gap-2">
                        <span class="{{ $unread ? 'font-bold' : 'font-medium' }}">{{ $req->client->name }}</span>
                        <span class="text-xs text-gray-400 font-mono">{{ $req->reference() }}</span>
                        @if ($req->delivery)
                            <span class="text-xs px-2 py-0.5 rounded-full bg-green-100 text-green-800">{{ $req->delivery->reference }}</span>
                        @endif
                    </div>
                    <p class="text-sm truncate {{ $unread ? 'text-gray-900' : 'text-gray-500' }}">
                        @if ($req->latestMessage?->media_id) 📷 Photo
                        @elseif ($req->latestMessage?->lat) 📍 Position
                        @else {{ $req->latestMessage?->body }}
                        @endif
                    </p>
                </div>
                <div class="text-right shrink-0">
                    <div class="text-xs text-gray-500">{{ $req->last_message_at?->diffForHumans() }}</div>
                    @if ($unread)
                        <span class="inline-block mt-1 w-3 h-3 rounded-full bg-red-600" title="Nouveau message"></span>
                    @endif
                </div>
            </a>
        @empty
            <p class="px-4 py-10 text-center text-gray-500">Aucune demande.</p>
        @endforelse
    </div>
    <div class="mt-4">{{ $requests->links() }}</div>
@endsection
