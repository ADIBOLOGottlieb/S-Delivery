<ul>
    @if ($supportPhone)
        <li>Téléphone / WhatsApp : <a href="tel:{{ preg_replace('/[^0-9+]/', '', $supportPhone) }}">{{ $supportPhone }}</a></li>
    @endif
    @if ($supportEmail)
        <li>Email : <a href="mailto:{{ $supportEmail }}">{{ $supportEmail }}</a></li>
    @endif
    @unless ($supportPhone || $supportEmail)
        <li>Depuis l'application : bouton « Contacter l'agence ».</li>
    @endunless
    <li>Adresse : S-Delivery, Lomé, Togo.</li>
</ul>
