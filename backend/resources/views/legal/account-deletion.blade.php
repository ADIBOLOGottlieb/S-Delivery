@extends('layouts.public')

@section('title', 'Supprimer mon compte')

@section('content')
    <h1>Supprimer mon compte VOOM Delivery</h1>
    <p class="muted">Vous pouvez supprimer votre compte à tout moment, gratuitement.</p>

    <h2>Depuis l'application (le plus simple)</h2>
    <div class="card">
        <ol class="steps">
            <li>Ouvrez l'application VOOM Delivery et connectez-vous.</li>
            <li>Allez dans <strong>Profil › Supprimer mon compte</strong>.</li>
            <li>Saisissez votre mot de passe pour confirmer. La suppression est immédiate.</li>
        </ol>
    </div>

    <h2>Sans l'application</h2>
    <p>Contactez l'agence depuis le numéro de téléphone (ou l'email) de votre compte et demandez la suppression ;
        elle est traitée sous 7 jours après vérification que la demande vient bien de vous.</p>
    @include('legal._contact')

    <h2>Ce qui est supprimé</h2>
    <ul>
        <li>Votre nom, votre numéro de téléphone, votre email et votre quartier sont effacés (remplacés par « Compte supprimé »).</li>
        <li>Votre photo de profil et le jeton de notification de votre téléphone sont supprimés.</li>
        <li>Vous êtes déconnecté de tous vos appareils ; plus personne ne peut se connecter à ce compte.</li>
        <li>Les livraisons non payées sont annulées et vos discussions avec l'agence sont clôturées.</li>
    </ul>

    <h2>Ce qui est conservé</h2>
    <p>L'historique des livraisons et des paiements (montants, dates, adresses de retrait et de livraison, références de transaction)
        est conservé, sans lien avec votre identité, pendant la durée exigée par les obligations comptables et fiscales
        (jusqu'à 10 ans), puis supprimé.</p>

    <h2>Quand la suppression n'est pas possible</h2>
    <p>Si une livraison est en cours (payée, en vérification de paiement, ou en route), attendez qu'elle soit livrée
        ou contactez l'agence : la suppression sera possible juste après.</p>

    <p><a class="btn" href="{{ route('legal.privacy') }}">Politique de confidentialité</a></p>
@endsection
