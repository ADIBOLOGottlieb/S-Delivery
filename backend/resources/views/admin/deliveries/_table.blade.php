<div class="overflow-x-auto">
    <table class="min-w-full text-sm">
        <thead class="bg-gray-50 text-left text-gray-500">
        <tr>
            <th class="px-4 py-2">Réf.</th>
            <th class="px-4 py-2">Client</th>
            <th class="px-4 py-2">Type</th>
            <th class="px-4 py-2">Trajet</th>
            <th class="px-4 py-2 text-right">Montant</th>
            <th class="px-4 py-2">Statut</th>
            <th class="px-4 py-2">Paiement</th>
            <th class="px-4 py-2">Livreur</th>
            <th class="px-4 py-2">Créée</th>
        </tr>
        </thead>
        <tbody class="divide-y">
        @forelse ($deliveries as $delivery)
            <tr class="hover:bg-yellow-50 cursor-pointer" onclick="window.location='{{ route('admin.deliveries.show', $delivery) }}'">
                <td class="px-4 py-2 font-mono font-semibold">
                    <a href="{{ route('admin.deliveries.show', $delivery) }}">{{ $delivery->reference }}</a>
                </td>
                <td class="px-4 py-2">{{ $delivery->client?->name }}<div class="text-xs text-gray-500">{{ $delivery->client?->phone_number }}</div></td>
                <td class="px-4 py-2">
                    {{ $delivery->type->label() }}
                    @if ($delivery->deadline_at)
                        <div class="text-xs {{ $delivery->deadline_at->isPast() && ! $delivery->status->isFinal() ? 'text-red-700 font-semibold' : 'text-gray-500' }}">
                            avant {{ $delivery->deadline_at->format('d/m H:i') }}
                        </div>
                    @endif
                </td>
                <td class="px-4 py-2 max-w-xs">
                    <div class="truncate"><span class="font-semibold text-green-700">A</span> {{ $delivery->pickup_address }}</div>
                    <div class="truncate"><span class="font-semibold text-red-700">B</span> {{ $delivery->dropoff_address }}</div>
                </td>
                <td class="px-4 py-2 text-right whitespace-nowrap">{{ number_format($delivery->total_amount, 0, ',', ' ') }} F</td>
                <td class="px-4 py-2"><span class="px-2 py-0.5 rounded-full text-xs whitespace-nowrap {{ $delivery->status->badgeClass() }}">{{ $delivery->status->label() }}</span></td>
                <td class="px-4 py-2">
                    <span class="px-2 py-0.5 rounded-full text-xs whitespace-nowrap {{ $delivery->payment_status->badgeClass() }}">{{ $delivery->payment_status->label() }}</span>
                    @if ($delivery->needsRefund())
                        <div class="mt-1"><span class="px-2 py-0.5 rounded-full text-xs whitespace-nowrap bg-red-600 text-white">À rembourser</span></div>
                    @endif
                </td>
                <td class="px-4 py-2">{{ $delivery->courier?->name ?? '—' }}</td>
                <td class="px-4 py-2 whitespace-nowrap text-gray-500">{{ $delivery->created_at->format('d/m H:i') }}</td>
            </tr>
        @empty
            <tr><td colspan="9" class="px-4 py-8 text-center text-gray-500">Aucune livraison.</td></tr>
        @endforelse
        </tbody>
    </table>
</div>
