@extends('layouts.admin')

@section('title', 'Livraisons')

@section('content')
    <h1 class="text-2xl font-bold mb-4">Livraisons</h1>

    <form method="GET" class="bg-white rounded-lg shadow-sm p-4 mb-4 flex flex-wrap gap-3 items-end">
        <div>
            <label class="block text-xs text-gray-500 mb-1">Recherche</label>
            <input name="search" value="{{ $filters['search'] ?? '' }}" placeholder="Réf., client, téléphone"
                   class="border rounded px-3 py-2 w-64">
        </div>
        <div>
            <label class="block text-xs text-gray-500 mb-1">Statut</label>
            <select name="status" class="border rounded px-3 py-2">
                <option value="">Tous</option>
                @foreach (\App\Enums\DeliveryStatus::cases() as $status)
                    <option value="{{ $status->value }}" @selected(($filters['status'] ?? '') === $status->value)>{{ $status->label() }}</option>
                @endforeach
            </select>
        </div>
        <div>
            <label class="block text-xs text-gray-500 mb-1">Paiement</label>
            <select name="payment_status" class="border rounded px-3 py-2">
                <option value="">Tous</option>
                @foreach (\App\Enums\PaymentStatus::cases() as $status)
                    <option value="{{ $status->value }}" @selected(($filters['payment_status'] ?? '') === $status->value)>{{ $status->label() }}</option>
                @endforeach
            </select>
        </div>
        <button class="bg-black text-brand rounded px-4 py-2 font-semibold">Filtrer</button>
        <a href="{{ route('admin.deliveries.index') }}" class="text-sm text-gray-500 py-2">Réinitialiser</a>
    </form>

    <div class="bg-white rounded-lg shadow-sm">
        @include('admin.deliveries._table')
    </div>
    <div class="mt-4">{{ $deliveries->links() }}</div>
@endsection
