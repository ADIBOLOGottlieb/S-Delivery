@extends('layouts.admin')

@section('title', 'Connexion')

@section('content')
    <div class="max-w-sm mx-auto mt-16 bg-white rounded-xl shadow p-8">
        <div class="text-center mb-6">
            <img src="{{ asset('images/s-delivery-logo.png') }}" alt="S-Delivery" class="mx-auto mb-4 h-12">
            <h1 class="sr-only">S-Delivery</h1>
            <p class="text-gray-500 text-sm">Panneau d'administration</p>
        </div>
        <form method="POST" action="{{ route('admin.login') }}" class="space-y-4">
            @csrf
            <div>
                <label class="block text-sm font-medium mb-1" for="email">Email</label>
                <input id="email" name="email" type="email" value="{{ old('email') }}" required autofocus
                       class="w-full rounded border-gray-300 border px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand">
            </div>
            <div>
                <label class="block text-sm font-medium mb-1" for="password">Mot de passe</label>
                <input id="password" name="password" type="password" required
                       class="w-full rounded border-gray-300 border px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand">
            </div>
            <label class="flex items-center gap-2 text-sm"><input type="checkbox" name="remember"> Rester connecté</label>
            <button class="w-full bg-black text-brand font-semibold rounded py-2.5 hover:bg-gray-800">Se connecter</button>
        </form>
    </div>
@endsection
