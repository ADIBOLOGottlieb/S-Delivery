<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>@yield('title', 'Administration') · VOOM Delivery</title>
    <link rel="icon" type="image/png" href="{{ asset('images/voom-icon.png') }}">
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
        tailwind.config = { theme: { extend: { colors: { voom: { DEFAULT: '#FAC223', dark: '#E0A800' } } } } };
    </script>
    @stack('head')
</head>
{{-- Fond : photo du livreur VOOM (casquette jaune) sous un voile crème, pour garder le contenu lisible. --}}
<body class="text-gray-900 min-h-screen"
      style="background: linear-gradient(rgba(255, 243, 214, 0.76), rgba(255, 243, 214, 0.80)), url('{{ asset('images/photo-courier.jpg') }}') center top / cover fixed no-repeat, #FFF3D6;">
@auth
    @php
        $nav = [
            ['admin.dashboard', 'Tableau de bord', 'admin.dashboard'],
            ['admin.deliveries.index', 'Livraisons', 'admin.deliveries.*'],
            ['admin.requests.index', 'Demandes', 'admin.requests.*'],
            ['admin.couriers.index', 'Livreurs', 'admin.couriers.*'],
            ['admin.clients.index', 'Clients', 'admin.clients.*'],
            ['admin.products.index', 'Courses alimentaires', 'admin.products.*'],
            ['admin.promotions.index', 'Promos', 'admin.promotions.*'],
            ['admin.settings.edit', 'Réglages', 'admin.settings.*'],
        ];
        $unreadRequests = \App\Http\Controllers\Admin\RequestController::unreadCount();
    @endphp
    <header class="bg-black text-white">
        <div class="max-w-7xl mx-auto px-4 flex flex-wrap items-center gap-x-6 gap-y-2 py-3">
            <a href="{{ route('admin.dashboard') }}" class="flex items-center gap-2">
                <img src="{{ asset('images/voom-logo-light.png') }}" alt="VOOM Delivery" class="h-10">
                <span class="font-light text-white text-lg">Admin</span>
            </a>
            <nav class="flex flex-wrap gap-1 text-sm flex-1">
                @foreach ($nav as [$route, $label, $pattern])
                    <a href="{{ route($route) }}"
                       class="px-3 py-1.5 rounded {{ request()->routeIs($pattern) ? 'bg-voom text-black font-semibold' : 'hover:bg-white/10' }}">{{ $label }}@if ($route === 'admin.requests.index' && $unreadRequests > 0)<span class="ml-1 inline-flex items-center justify-center min-w-5 h-5 px-1 rounded-full bg-red-600 text-white text-xs font-bold">{{ $unreadRequests }}</span>@endif</a>
                @endforeach
            </nav>
            <form method="POST" action="{{ route('admin.logout') }}">
                @csrf
                <button class="text-sm text-gray-300 hover:text-white">{{ auth()->user()->name }} · Déconnexion</button>
            </form>
        </div>
    </header>
@endauth

<main class="max-w-7xl mx-auto px-4 py-6">
    @if (session('success'))
        <div class="mb-4 rounded border border-green-300 bg-green-50 px-4 py-3 text-green-800">{{ session('success') }}</div>
    @endif
    @if ($errors->any())
        <div class="mb-4 rounded border border-red-300 bg-red-50 px-4 py-3 text-red-800">
            <ul class="list-disc pl-5">
                @foreach ($errors->all() as $error)
                    <li>{{ $error }}</li>
                @endforeach
            </ul>
        </div>
    @endif

    @yield('content')
</main>
@stack('scripts')
</body>
</html>
