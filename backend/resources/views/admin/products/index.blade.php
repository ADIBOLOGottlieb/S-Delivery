@extends('layouts.admin')

@section('title', 'Courses alimentaires')

@section('content')
    @php
        $tab = fn (bool $active) => 'shrink-0 px-4 py-2 rounded-full text-sm font-medium '
            .($active ? 'bg-black text-voom' : 'bg-white text-gray-700 hover:bg-gray-50 shadow-sm');
    @endphp

    <div class="flex flex-wrap items-center justify-between gap-3 mb-4">
        <div>
            <h1 class="text-2xl font-bold">🧺 Courses alimentaires</h1>
            <p class="text-sm text-gray-500">Mêmes sous-onglets que dans l'app. <a href="{{ route('admin.subcategories.index') }}" class="underline">Renommer / réordonner les sous-catégories</a></p>
        </div>
        <div class="flex gap-2">
            <a href="{{ route('admin.products.create', ['type' => 'pack']) }}" class="border border-black font-semibold rounded px-4 py-2">+ Nouveau pack</a>
            <a href="{{ route('admin.products.create', array_filter(['subcategory' => $subcategoryId])) }}" class="bg-black text-voom font-semibold rounded px-4 py-2">+ Nouveau produit</a>
        </div>
    </div>

    {{-- Sous-onglets : Tout, sous-catégories (ordre de l'app), Autres produits, Packs en dernier. --}}
    <nav class="flex gap-2 overflow-x-auto pb-2 mb-4">
        <a href="{{ route('admin.products.index') }}" class="{{ $tab(! $subcategoryId && ! $others && $type !== 'pack') }}">Tout</a>
        @foreach ($subcategories as $sub)
            <a href="{{ route('admin.products.index', ['subcategory' => $sub->id]) }}" class="{{ $tab($subcategoryId === $sub->id) }}">
                {{ $sub->name }} <span class="opacity-60">({{ $sub->products_count }})</span>
            </a>
        @endforeach
        <a href="{{ route('admin.products.index', ['subcategory' => 'others']) }}" class="{{ $tab($others) }}" title="Produits sans famille (ex. œufs)">
            Autres produits <span class="opacity-60">({{ $othersCount }})</span>
        </a>
        <a href="{{ route('admin.products.index', ['type' => 'pack']) }}" class="{{ $tab($type === 'pack') }}">
            Packs <span class="opacity-60">({{ $packsCount }})</span>
        </a>
    </nav>

    <div class="grid sm:grid-cols-2 lg:grid-cols-4 gap-4">
        @forelse ($products as $product)
            <div class="bg-white rounded-lg shadow-sm overflow-hidden {{ $product->is_active ? '' : 'opacity-60' }}">
                @if ($product->imageUrl())
                    <img src="{{ $product->imageUrl() }}" alt="" class="w-full h-40 object-cover">
                @else
                    <div class="w-full h-40 bg-gray-100 flex items-center justify-center text-4xl">📦</div>
                @endif
                <div class="p-4">
                    <div class="text-xs text-gray-500">
                        {{ $product->isPack() ? 'Packs' : ($product->subcategory?->name ?? 'Autres produits') }}
                        · {{ $product->vendor_name ?? 'VOOM' }}
                    </div>
                    <div class="font-semibold">
                        @if ($product->isPack())<span class="text-xs bg-black text-voom rounded px-1.5 py-0.5 mr-1">PACK</span>@endif
                        {{ $product->name }}
                    </div>
                    <div class="text-sm">{{ number_format($product->price, 0, ',', ' ') }} F {{ $product->unit ? '/ '.$product->unit : '' }}</div>
                    @unless ($product->is_active)<div class="text-xs text-red-700">Masqué</div>@endunless
                    <div class="flex gap-3 mt-3 text-sm">
                        <a href="{{ route('admin.products.edit', $product) }}" class="text-blue-600 underline">Modifier</a>
                        <form method="POST" action="{{ route('admin.products.destroy', $product) }}" onsubmit="return confirm('Supprimer ce produit ?')">
                            @csrf @method('DELETE')
                            <button class="text-red-700 underline">Supprimer</button>
                        </form>
                    </div>
                </div>
            </div>
        @empty
            <p class="text-gray-500">Aucun produit.</p>
        @endforelse
    </div>
    <div class="mt-4">{{ $products->links() }}</div>
@endsection
