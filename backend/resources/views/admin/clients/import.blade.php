@extends('layouts.admin')

@section('title', 'Importer des clients')

@section('content')
    <a href="{{ route('admin.clients.index') }}" class="text-gray-500">← Clients</a>
    <h1 class="text-2xl font-bold mt-2 mb-4">Importer vos anciens clients</h1>

    <div class="grid lg:grid-cols-2 gap-6 max-w-5xl">
        <form method="POST" action="{{ route('admin.clients.import.store') }}" enctype="multipart/form-data"
              class="bg-white rounded-lg shadow-sm p-6 space-y-4">
            @csrf
            <div>
                <label class="block text-sm font-medium mb-1">Fichier CSV</label>
                <input type="file" name="file" accept=".csv,.txt,text/csv" required class="w-full border rounded px-3 py-2">
            </div>
            <button class="bg-black text-voom font-semibold rounded px-6 py-2">Importer</button>
            <p class="text-xs text-gray-500">
                Chaque client reçoit un mot de passe de 8 chiffres.
                Les numéros déjà inscrits ou en double sont ignorés (rien n'est écrasé).
                {{ \App\Http\Controllers\Admin\ClientAccountController::MAX_IMPORT_ROWS }} clients maximum par fichier :
                découpez les listes plus longues en plusieurs fichiers.
            </p>
        </form>

        <section class="bg-white rounded-lg shadow-sm p-6 text-sm space-y-3">
            <h2 class="font-semibold">Préparer le fichier dans Excel</h2>
            <ol class="list-decimal pl-5 space-y-1 text-gray-700">
                <li>Une ligne par client, colonnes : <strong>nom</strong>, <strong>téléphone</strong>, <strong>quartier</strong> (facultatif).</li>
                <li>Une ligne d'en-tête est acceptée (« Nom ; Téléphone ; Quartier »).</li>
                <li>Fichier › Enregistrer sous › <strong>CSV UTF-8</strong> (ou CSV séparateur point-virgule).</li>
            </ol>
            <p class="text-gray-500">Exemple :</p>
            <pre class="bg-gray-50 border rounded p-3 text-xs">Nom;Téléphone;Quartier
Ama Mensah;90 11 22 33;Agoè
Kossi Adjo;+228 91 22 33 44;Bè Kpota</pre>
            <p class="text-gray-500">Les numéros sont acceptés sous toutes les formes (8 chiffres, 228…, +228…) et enregistrés en +228XXXXXXXX.</p>
        </section>
    </div>
@endsection
