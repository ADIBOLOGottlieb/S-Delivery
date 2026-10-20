# S-Delivery

Application de livraison de plis et colis à Lomé (Togo). Le client commande une course d'un **point A** (récupération) à un **point B** (destination), **paie directement dans l'app** (Flooz, Mixx by Yas ou carte bancaire), suit son **livreur en direct sur la carte**, lui **écrit** et donne au destinataire un **code de remise** à 4 chiffres. L'agence pilote tout depuis le panneau d'administration web.

| Dossier | Contenu |
|---|---|
| `lib/` | Application mobile Flutter (clients et livreurs) |
| `backend/` | API REST + panneau d'administration web (Laravel 13, Sanctum) |
| `render.yaml` | Déploiement de l'API sur Render (Blueprint) |

## Fonctionnement

```
Client                               Admin (web /admin)                    Livreur
──────                               ──────────────────                    ───────
1. « Où livrer ? » : A → B sur la carte,
   taille (pli, colis, gros colis),
   maintenant ou programmée → prix
2. Paie dans l'app (Flooz, Mixx, carte)
   → confirmé automatiquement ─────▶ 3. Assigne un livreur actif ─────▶ 4. Voit la course : carte, itinéraire,
   (repli : virement + capture                                              appel, discussion avec le client
    vérifiée par l'agence)                                               5. Sa position est partagée pendant la course
6. Suit le livreur en direct,                                            6. « Colis récupéré » puis « Colis remis »
   discute avec lui                                                         avec le code donné par le destinataire
7. Note le livreur (1 à 5 étoiles)
```

- **Rôles** : `client` (inscription libre), `livreur` (créé par l'admin), `admin` (panneau web).
- **Accueil** : barre « Où livrer ? », course en cours (progression en direct, messages non lus), services *Envoyer*, *Recevoir*, *Programmer*, *Par photo*, adresses récentes.
- **Commande par photo** : une simple photo du colis suffit ; l'agence complète l'adresse avec le client dans la discussion puis programme la livraison.
- **Discussion de la course** : client, livreur et agence échangent texte, photos et positions ; chaque message envoie une notification ; l'agence répond depuis la fiche de la livraison.
- **Suivi en direct** : l'app du livreur envoie sa position (au plus toutes les 15 s, pendant une course seulement) ; le client la voit sur la carte tant qu'elle date de moins de 10 minutes.
- **Code de remise** : 4 chiffres créés avec la course, visibles du client seul (il peut l'envoyer par SMS au destinataire) ; le livreur doit le saisir pour clôturer la course. L'agence le voit dans la fiche si le destinataire ne l'a pas.
- **Note** : après la livraison, le client note le livreur (étoiles + commentaire), visible dans l'admin.
- **Tarif** : forfait + distance estimée × prix/km, minimum configurable, arrondi à 50 F (*Admin › Réglages*).

## Paiement intégré

| Agrégateur | Moyens | Frais | Fonctionnement |
|---|---|---|---|
| **KKiaPay** (recommandé) | Flooz, Mixx by Yas, **carte bancaire** | 1,9 % payés par le client + abonnement | page de paiement sécurisée ouverte depuis l'app |
| **PayGate Global** | Flooz, Mixx by Yas | 2,5 % / 3 % payés par l'agence | demande envoyée sur le téléphone, validée avec le code secret |

Sécurité : chaque paiement est **revérifié côté serveur** auprès de l'agrégateur (les webhooks ne font que déclencher la vérification), le montant est contrôlé, une transaction ne paie qu'une livraison, une seconde demande est bloquée tant qu'un paiement est en cours, et la course ne peut pas être annulée pendant la validation.

Mise en service :
1. Variables Render (ou `.env`) : `PAYMENT_GATEWAY=kkiapay` + `KKIAPAY_PUBLIC_KEY`, `KKIAPAY_PRIVATE_KEY`, `KKIAPAY_SECRET` (`KKIAPAY_SANDBOX=false` en production), ou `PAYMENT_GATEWAY=paygate` + `PAYGATE_AUTH_TOKEN`.
2. Déclarer chez l'agrégateur l'URL de notification affichée dans *Admin › Réglages*.
3. *Admin › Réglages › Mode de paiement* : **Automatique** (paiement dans l'app), **Manuel** (virement au numéro marchand + capture vérifiée par l'agence) ou **Simulation** (démonstration, aucun argent débité).

Sans clés, l'app repasse automatiquement en mode manuel. L'admin peut toujours valider un paiement reçu autrement (espèces…) depuis la fiche d'une livraison.

## Identité visuelle

Design inspiré des apps de mobilité : fonds blancs, noir d'encre `#0A0A0A` pour l'action, gris neutres, un seul accent **lime `#C6FF3D`**, police **Inter** embarquée (`assets/fonts`). Le logo est un « S » tracé comme un itinéraire, avec un point de départ et un point d'arrivée.

| Fichier | Usage |
|---|---|
| `lib/widgets/brand_logo.dart` | Logo vectoriel dans l'app (`SDeliveryMark`, `SDeliveryLogo`) |
| `assets/images/s_delivery_icon.png` · `s_delivery_icon_foreground.png` | Sources des icônes (`dart run flutter_launcher_icons`) |
| `backend/public/images/s-delivery-*.png` | Panneau admin, page de paiement, favicon |

## Notifications push (Firebase, gratuit sans carte bancaire)

Suivi des courses et messages pour les clients, nouvelles courses et rappels (Express, heure limite) pour les livreurs.

1. https://console.firebase.google.com › **Créer un projet** (plan Spark gratuit).
2. **Ajouter une application Android**, nom de paquet `com.voomdelivery.app` › télécharger `google-services.json`.
3. GitHub › Settings › Secrets › Actions : `GOOGLE_SERVICES_JSON` (base64) et `CRON_SECRET` (même valeur que sur Render).
4. Firebase › Comptes de service › « Générer une nouvelle clé privée » › JSON en base64 dans Render › `FIREBASE_CREDENTIALS`.
5. Relancer le build de l'APK (Actions › Build APK › Run workflow).

Sans ces réglages, l'application fonctionne normalement, sans notifications.

## Démarrage en local

### 1. Backend

Prérequis : PHP 8.3+, Composer.

```bash
cd backend
composer install
cp .env.example .env          # puis ajuster ADMIN_EMAIL / ADMIN_PASSWORD (et PAYMENT_GATEWAY)
php artisan key:generate
php artisan migrate --seed    # SQLite par défaut ; crée l'admin + données de démo
php artisan serve --host=0.0.0.0 --port=8000
```

- Panneau admin : http://localhost:8000/admin.
- Comptes de démo (hors production) : client `client@sdelivery.tg`, livreur `livreur@sdelivery.tg`, mot de passe `password123`.
- Tests : `php artisan test`.

### 2. Application Flutter

Prérequis : Flutter 3.35+ ; sous Windows, activer le **Mode développeur**.

```bash
flutter pub get
flutter run                                                     # émulateur Android
flutter run --dart-define=API_BASE_URL=http://IP_DU_PC:8000/api/v1   # téléphone sur le même Wi-Fi
```

Cartes **OpenStreetMap** (`flutter_map`) et adresses via **Nominatim**, sans clé. En release, l'app utilise `https://voom-delivery-api.onrender.com/api/v1`.

Tests : `flutter test` · analyse : `flutter analyze`.

## Déploiement de l'API sur Render

1. Render › **New** › **Blueprint** › ce dépôt : `render.yaml` crée le service **`voom-delivery-api`** (Docker, `backend/`) et la base PostgreSQL.
2. Renseigner `ADMIN_EMAIL`, `ADMIN_PHONE`, `ADMIN_PASSWORD` et les clés de paiement.
3. Au démarrage, le conteneur exécute les migrations et crée le compte admin.

> ⚠️ Plan gratuit : la base PostgreSQL gratuite expire après 30 jours. Pour la production, passer en plan payant.

## API (préfixe `/api/v1`, jeton `Authorization: Bearer …`)

| Méthode | Route | Rôle | Description |
|---|---|---|---|
| POST | `/register` · `/login` | public | Inscription client · connexion (email ou téléphone) |
| GET | `/me` · POST `/logout` | connecté | Profil · déconnexion |
| GET | `/payment-info` | connecté | Paiement en ligne (`online`), numéros marchands, contact |
| POST | `/deliveries/quote` | client | Estimation du prix |
| GET/POST | `/deliveries` | client | Mes livraisons · nouvelle course |
| GET | `/deliveries/{id}` | client | Détail (code de remise, position du livreur, non-lus) |
| POST | `/deliveries/{id}/checkout` | client | Paiement intégré (`method` flooz/mixx/card, `phone`) |
| GET | `/deliveries/{id}/payments/{p}` | client | Statut du paiement (revérifié auprès de l'agrégateur) |
| POST | `/deliveries/{id}/payment` | client | Paiement manuel : preuve (`screenshot`) |
| POST | `/deliveries/{id}/cancel` · `/photos` · `/rating` | client | Annulation · photo d'article · note du livreur |
| GET/POST | `/deliveries/{id}/messages` | client | Discussion de la course |
| GET/POST | `/requests` · `/requests/{id}/messages` | client | Commande par photo et discussion avec l'agence |
| GET | `/courier/deliveries[?scope=history]` · `/courier/deliveries/{id}` | livreur | Courses assignées |
| POST | `/courier/deliveries/{id}/status` | livreur | `picked_up` puis `delivered` (+ `code` de remise) |
| GET/POST | `/courier/deliveries/{id}/messages` | livreur | Discussion avec le client |
| POST | `/courier/location` | livreur | Position pendant la course |
| POST | `/webhooks/kkiapay` · `/webhooks/paygate` | agrégateur | Notifications (revérifiées) |
