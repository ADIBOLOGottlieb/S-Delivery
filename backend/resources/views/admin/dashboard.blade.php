@extends('layouts.admin')

@section('title', 'Tableau de bord')

@section('content')
    <h1 class="text-2xl font-bold mb-6">Tableau de bord</h1>

    @php
        $cards = [
            ['Paiements à vérifier', $paymentsToReview, route('admin.deliveries.index', ['payment_status' => 'submitted']), 'border-orange-400'],
            ['Livraisons à assigner', $toAssign, route('admin.deliveries.index', ['status' => 'pending', 'payment_status' => 'verified']), 'border-brand'],
            ['En cours', $inProgress, route('admin.deliveries.index', ['status' => 'assigned']), 'border-blue-400'],
            ['Livrées aujourd\'hui', $deliveredToday, route('admin.deliveries.index', ['status' => 'delivered']), 'border-green-500'],
            ['Livreurs actifs', $activeCouriers, route('admin.couriers.index'), 'border-gray-400'],
            ['Frais livrés ce mois', number_format($revenueMonth, 0, ',', ' ').' F', route('admin.deliveries.index', ['status' => 'delivered', 'payment_status' => 'verified']), 'border-black'],
        ];
    @endphp

    <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4 mb-8">
        @foreach ($cards as [$label, $value, $url, $border])
            <a href="{{ $url }}" class="bg-white rounded-lg shadow-sm p-4 border-l-4 {{ $border }} hover:shadow">
                <div class="text-sm text-gray-500">{{ $label }}</div>
                <div class="text-2xl font-bold mt-1">{{ $value }}</div>
            </a>
        @endforeach
    </div>

    <div class="bg-white rounded-lg shadow-sm">
        <div class="px-4 py-3 border-b font-semibold">Dernières demandes</div>
        @include('admin.deliveries._table', ['deliveries' => $latest])
    </div>
@endsection
