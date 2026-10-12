@extends('layouts.admin')

@section('title', $request->reference())

@push('head')
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
@endpush

@section('content')
    @php
        $client = $request->client;
        $money = fn ($v) => number_format($v, 0, ',', ' ').' FCFA';
    @endphp

    <div class="flex flex-wrap items-center gap-3 mb-4">
        <a href="{{ route('admin.requests.index') }}" class="text-gray-500">← Demandes</a>
        <h1 class="text-2xl font-bold">{{ $client->name }}</h1>
        <span class="text-sm text-gray-500 font-mono">{{ $request->reference() }}</span>
        <span class="px-2 py-0.5 rounded-full text-xs bg-gray-200">{{ $request->statusLabel() }}</span>
        <a href="tel:{{ $client->phone_number }}" class="text-sm text-blue-600 underline">{{ $client->phone_number }}</a>
    </div>

    @if ($request->district)
        <div class="mb-4 flex flex-wrap gap-3 text-sm">
            <span class="bg-white rounded-lg shadow-sm px-3 py-2">📍 Quartier : <strong>{{ $request->district }}</strong></span>
            <span class="bg-white rounded-lg shadow-sm px-3 py-2">📞 Numéro : <a class="font-semibold underline" href="tel:{{ $request->recipient_phone }}">{{ $request->recipient_phone }}</a></span>
            <span class="bg-white rounded-lg shadow-sm px-3 py-2">💰 Montant total du colis : <strong>{{ $money($request->parcel_amount) }}</strong></span>
        </div>
    @endif

    <div class="grid lg:grid-cols-5 gap-6">
        {{-- Discussion --}}
        <section class="lg:col-span-3 bg-white rounded-lg shadow-sm flex flex-col" style="height: 75vh">
            <div id="thread" class="flex-1 overflow-y-auto p-4 space-y-3 bg-[#f4efe6]">
                @foreach ($request->messages as $m)
                    @php($fromClient = $m->sender_id === $client->id)
                    @if ($m->sender_id === null)
                        <div class="text-center">
                            <span class="inline-block text-xs bg-white/80 text-gray-600 rounded-full px-3 py-1">{{ $m->body }}</span>
                        </div>
                    @else
                        <div class="flex {{ $fromClient ? 'justify-start' : 'justify-end' }}">
                            <div class="max-w-[75%] rounded-2xl px-3 py-2 shadow-sm {{ $fromClient ? 'bg-white rounded-tl-sm' : 'bg-voom rounded-tr-sm' }}">
                                @if ($m->media)
                                    <a href="{{ $m->media->url() }}" target="_blank">
                                        <img src="{{ $m->media->url() }}" alt="Photo" class="rounded-lg max-h-64 object-cover">
                                    </a>
                                @endif
                                @if ($m->lat !== null)
                                    <div class="text-sm">
                                        📍 <a class="underline" target="_blank" href="https://www.google.com/maps/search/?api=1&query={{ $m->lat }},{{ $m->lng }}">Position partagée</a>
                                        @unless ($request->delivery_id)
                                            <span class="ml-2 whitespace-nowrap">
                                                <button type="button" class="text-xs bg-green-600 text-white rounded px-2 py-0.5" onclick="voomSetPoint('pickup', {{ $m->lat }}, {{ $m->lng }})">→ A</button>
                                                <button type="button" class="text-xs bg-red-600 text-white rounded px-2 py-0.5" onclick="voomSetPoint('dropoff', {{ $m->lat }}, {{ $m->lng }})">→ B</button>
                                            </span>
                                        @endunless
                                    </div>
                                @endif
                                @if ($m->body)
                                    <p class="whitespace-pre-line text-sm {{ $m->media ? 'mt-1' : '' }}">{{ $m->body }}</p>
                                @endif
                                <div class="text-[10px] text-gray-500 text-right mt-0.5">
                                    {{ $fromClient ? '' : ($m->sender?->name.' · ') }}{{ $m->created_at->format('d/m H:i') }}
                                </div>
                            </div>
                        </div>
                    @endif
                @endforeach
            </div>

            <form method="POST" action="{{ route('admin.requests.reply', $request) }}" enctype="multipart/form-data"
                  class="border-t p-3 flex items-end gap-2" id="reply-form">
                @csrf
                <label class="cursor-pointer text-2xl px-2" title="Envoyer une photo">
                    📎<input type="file" name="photo" accept="image/*" class="hidden" onchange="this.form.submit()">
                </label>
                <textarea name="body" rows="2" placeholder="Votre message… (prix, heure de passage, question)"
                          class="flex-1 border rounded-lg px-3 py-2 resize-none"
                          onkeydown="if (event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); this.form.submit(); }"></textarea>
                <button class="bg-black text-voom font-semibold rounded-lg px-4 py-2">Envoyer</button>
            </form>
        </section>

        {{-- Programmation --}}
        <aside class="lg:col-span-2 space-y-6">
            @if ($request->delivery)
                @php($d = $request->delivery)
                <section class="bg-white rounded-lg shadow-sm p-5">
                    <h2 class="font-semibold mb-2">Livraison programmée</h2>
                    <a href="{{ route('admin.deliveries.show', $d) }}" class="text-lg font-mono font-bold underline">{{ $d->reference }}</a>
                    <div class="flex gap-2 mt-2">
                        <span class="px-2 py-0.5 rounded-full text-xs {{ $d->status->badgeClass() }}">{{ $d->status->label() }}</span>
                        <span class="px-2 py-0.5 rounded-full text-xs {{ $d->payment_status->badgeClass() }}">{{ $d->payment_status->label() }}</span>
                    </div>
                    <p class="text-sm text-gray-600 mt-3">{{ $d->pickup_address }} → {{ $d->dropoff_address }}</p>
                    <p class="font-semibold mt-1">{{ $money($d->total_amount) }}</p>
                    <p class="text-xs text-gray-500 mt-3">Validez le paiement puis assignez un livreur depuis la fiche de la livraison.</p>
                </section>
            @else
                <section class="bg-white rounded-lg shadow-sm p-5">
                    <h2 class="font-semibold mb-1">Programmer la livraison</h2>
                    <p class="text-xs text-gray-500 mb-4">Cliquez sur la carte ou cherchez une adresse pour placer A et B. Les photos de la discussion seront jointes à la livraison.</p>

                    <form method="POST" action="{{ route('admin.requests.schedule', $request) }}" id="schedule-form" class="space-y-4 text-sm">
                        @csrf
                        <div>
                            <label class="block text-gray-600 mb-1">Type</label>
                            <select name="type" class="w-full border rounded px-3 py-2" onchange="document.getElementById('sched').classList.toggle('hidden', this.value !== 'programmee')">
                                @foreach (\App\Enums\DeliveryType::cases() as $type)
                                    <option value="{{ $type->value }}" @selected(old('type', 'colis') === $type->value)>{{ $type->label() }}</option>
                                @endforeach
                            </select>
                        </div>
                        <div id="sched" class="{{ old('type') === 'programmee' ? '' : 'hidden' }}">
                            <label class="block text-gray-600 mb-1">Date et heure de passage</label>
                            <input type="datetime-local" name="scheduled_at" value="{{ old('scheduled_at') }}" class="w-full border rounded px-3 py-2">
                        </div>

                        @foreach ([
                            'pickup' => ['A · Récupération', 'text-green-700', $previous?->pickup_address, $previous?->pickup_lat, $previous?->pickup_lng],
                            'dropoff' => ['B · Destination', 'text-red-700', $request->district, null, null],
                        ] as $key => [$title, $color, $addr, $lat, $lng])
                            <fieldset class="border rounded-lg p-3 space-y-2">
                                <legend class="px-1 font-semibold {{ $color }}">{{ $title }}</legend>
                                <div class="flex gap-2">
                                    <input id="{{ $key }}-search" placeholder="Chercher (quartier, repère…)" class="flex-1 border rounded px-3 py-2"
                                           onkeydown="if (event.key === 'Enter') { event.preventDefault(); voomSearch('{{ $key }}'); }">
                                    <button type="button" class="border rounded px-3" onclick="voomSearch('{{ $key }}')">🔍</button>
                                </div>
                                <div id="{{ $key }}-map" class="h-44 rounded border"></div>
                                <input name="{{ $key }}_address" id="{{ $key }}-address" required value="{{ old($key.'_address', $addr) }}"
                                       placeholder="Adresse / repère" class="w-full border rounded px-3 py-2">
                                <input type="hidden" name="{{ $key }}_lat" id="{{ $key }}-lat" value="{{ old($key.'_lat', $lat) }}">
                                <input type="hidden" name="{{ $key }}_lng" id="{{ $key }}-lng" value="{{ old($key.'_lng', $lng) }}">
                                @if ($key === 'pickup')
                                    <div class="grid grid-cols-2 gap-2">
                                        <input name="pickup_contact_name" value="{{ old('pickup_contact_name', $client->name) }}" placeholder="Contact" class="border rounded px-3 py-2">
                                        <input name="pickup_contact_phone" value="{{ old('pickup_contact_phone', $client->phone_number) }}" placeholder="Téléphone" class="border rounded px-3 py-2">
                                    </div>
                                @else
                                    <div class="grid grid-cols-2 gap-2">
                                        <input name="recipient_name" required value="{{ old('recipient_name') }}" placeholder="Destinataire" class="border rounded px-3 py-2">
                                        <input name="recipient_phone" required value="{{ old('recipient_phone', $request->recipient_phone) }}" placeholder="Téléphone" class="border rounded px-3 py-2">
                                    </div>
                                @endif
                            </fieldset>
                        @endforeach

                        <textarea name="package_description" rows="2" placeholder="Contenu (ex. 2 robes, 1 sac)" class="w-full border rounded px-3 py-2">{{ old('package_description') }}</textarea>
                        <textarea name="notes" rows="2" placeholder="Instructions pour le livreur" class="w-full border rounded px-3 py-2">{{ old('notes', $request->parcel_amount ? 'Montant total du colis : '.$money($request->parcel_amount) : '') }}</textarea>
                        <div class="grid grid-cols-2 gap-2">
                            <div>
                                <label class="block text-gray-600 mb-1">Heure limite</label>
                                <input type="datetime-local" name="deadline_at" value="{{ old('deadline_at') }}" class="w-full border rounded px-3 py-2">
                            </div>
                            <div>
                                <label class="block text-gray-600 mb-1">Frais (FCFA)</label>
                                <input type="number" name="delivery_fee" min="0" step="50" value="{{ old('delivery_fee') }}" placeholder="Auto (distance)" class="w-full border rounded px-3 py-2">
                            </div>
                        </div>
                        <button class="w-full bg-black text-voom font-semibold rounded-lg py-3">Programmer et prévenir le client</button>
                    </form>
                </section>
            @endif

            @if ($request->status === \App\Models\DeliveryRequest::OPEN)
                <form method="POST" action="{{ route('admin.requests.close', $request) }}"
                      onsubmit="return confirm('Clôturer cette demande sans livraison ?')">
                    @csrf
                    <button class="w-full border border-gray-400 text-gray-600 rounded-lg py-2 text-sm">Clôturer sans livraison</button>
                </form>
            @endif
        </aside>
    </div>
@endsection

@push('scripts')
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
    <script>
        const thread = document.getElementById('thread');
        thread.scrollTop = thread.scrollHeight;

        // Rafraîchit la discussion toutes les 20 s, sauf si l'admin est en train de remplir un formulaire.
        setInterval(() => {
            const busy = [...document.querySelectorAll('textarea, input:not([type=hidden])')]
                .some(el => el.matches(':focus') || (el.closest('#reply-form') && el.value));
            if (!busy && !document.getElementById('schedule-form')?.dataset.touched) location.reload();
        }, 20000);
        document.getElementById('schedule-form')?.addEventListener('input', e => e.currentTarget.dataset.touched = '1');

        // Cartes OpenStreetMap (gratuites) pour placer A et B.
        const LOME = [6.1319, 1.2228];
        const maps = {};
        const markers = {};
        const short = name => name.split(',').slice(0, 3).join(',');

        function voomSetPoint(key, lat, lng, label) {
            document.getElementById(key + '-lat').value = (+lat).toFixed(7);
            document.getElementById(key + '-lng').value = (+lng).toFixed(7);
            document.getElementById('schedule-form')?.setAttribute('data-touched', '1');
            const map = maps[key];
            if (!map) return;
            if (markers[key]) markers[key].setLatLng([lat, lng]);
            else markers[key] = L.marker([lat, lng]).addTo(map);
            map.setView([lat, lng], 16);
            const address = document.getElementById(key + '-address');
            if (label) address.value = label;
            else if (!address.value) {
                fetch(`https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}&zoom=18&accept-language=fr`)
                    .then(r => r.json())
                    .then(j => { if (!address.value && j.display_name) address.value = short(j.display_name); })
                    .catch(() => {});
            }
        }

        function voomSearch(key) {
            const q = document.getElementById(key + '-search').value.trim();
            if (!q) return;
            fetch(`https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=tg&accept-language=fr&q=${encodeURIComponent(q)}`)
                .then(r => r.json())
                .then(results => {
                    if (!results.length) return alert('Adresse introuvable : cliquez directement sur la carte.');
                    voomSetPoint(key, results[0].lat, results[0].lon, short(results[0].display_name));
                })
                .catch(() => alert('Recherche indisponible : cliquez sur la carte.'));
        }

        ['pickup', 'dropoff'].forEach(key => {
            const el = document.getElementById(key + '-map');
            if (!el) return;
            const map = L.map(el).setView(LOME, 13);
            L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '© OpenStreetMap' }).addTo(map);
            maps[key] = map;
            map.on('click', e => voomSetPoint(key, e.latlng.lat, e.latlng.lng));
            const lat = document.getElementById(key + '-lat').value;
            const lng = document.getElementById(key + '-lng').value;
            if (lat && lng) voomSetPoint(key, lat, lng, document.getElementById(key + '-address').value || undefined);
        });
        if (document.getElementById('schedule-form')) document.getElementById('schedule-form').dataset.touched = '';

        document.getElementById('schedule-form')?.addEventListener('submit', e => {
            for (const key of ['pickup', 'dropoff']) {
                if (!document.getElementById(key + '-lat').value) {
                    e.preventDefault();
                    return alert(`Placez le point ${key === 'pickup' ? 'A' : 'B'} sur la carte.`);
                }
            }
            if (!confirm('Créer la livraison et prévenir le client ?')) e.preventDefault();
        });
    </script>
@endpush
