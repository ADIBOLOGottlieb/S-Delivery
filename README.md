# VOOM Delivery

Application de livraison à Lomé (Togo) : le client demande une livraison d'un **point A** (récupération du colis) à un **point B** (destination), paie par **Flooz** ou **Mixx by Yas** sur le compte marchand de l'agence et envoie la **capture d'écran** de la transaction. L'agence vérifie le paiement et assigne un **livreur**, qui suit la course sur la carte et ouvre l'itinéraire dans Google Maps.

Le dépôt contient :

| Dossier | Contenu |
|---|---|
| `lib/` | Application mobile Flutter (clients et livreurs) |
| `backend/` | API REST + panneau d'administration web (Laravel 13, Sanctum) |
| `render.yaml` | Déploiement de l'API sur Render (Blueprint) |

## Fonctionnement

```
Client                         Admin (web /admin)                 Livreur
──────                         ──────────────────                 ───────
1. Demande A → B (carte)
   prix calculé (distance)
2. Paie Flooz / Mixx
   au numéro marchand ──▶ 3. Vérifie la capture et confirme
   + capture d'écran          (ou valide un paiement en espèces)
                            4. Assigne un livreur actif  ──▶ 5. Voit la livraison assignée
                                                             carte A/B, itinéraire, appel
                                                          6. « Colis récupéré » puis « Livré »
7. Suit le statut en temps réel
```

- **Rôles** : `client` (inscription libre dans l'app), `livreur` (compte créé par l'admin uniquement), `admin` (panneau web).
- **Accueil** : 3 services en ronds photo — Plis & Colis, Programmée, Courses alimentaires.
- **Deux façons de commander** (bouton central « Livrer » ou rond Plis & Colis) :
  - *formulaire* : A et B sur la carte, type, heure limite + photos des articles (6 max) ;
  - *programmation par photo* (tuile sous les types de livraison, ouverte à tout client connecté, au même titre que le formulaire) : **une simple photo du colis suffit** (écran à gros boutons, pensé pour les commerçants qui lisent peu ; l'agence saisit quartier, numéro et montant total du colis) ; l'agence discute avec lui dans *Admin › Demandes* (texte, photos, positions partagées) puis **programme la livraison** (A/B sur une carte OpenStreetMap, prix auto ou convenu). Le client reçoit une notification et paie depuis la discussion. Les photos accompagnent la livraison jusqu'au livreur.
- **Photo de profil** : client et livreur l'ajoutent / la changent depuis l'onglet Profil. Les photos (profil, articles, chat) sont stockées en base de données, elles survivent donc aux redémarrages de Render (disque éphémère).
- **Marketplace** (« Courses alimentaires » dans l'app, sous-onglets Poissons et fruits de mer, Légumes, Céréales et conserves, Fruits, Viandes, Packs) : produits gérés par l'admin. Une commande crée une livraison dont le point A est l'adresse du vendeur ; le total = articles + frais de livraison.
- **Tarif** : forfait + distance estimée × prix/km (+ supplément Express), minimum configurable, arrondi à 50 F. Réglable dans *Admin › Réglages*.
- **Paiement** : Flooz et Mixx by Yas par virement au numéro marchand + capture d'écran vérifiée par l'admin (voir ci-dessous). Un livreur ne peut être assigné qu'après confirmation du paiement.

## Paiement Flooz / Mixx by Yas (sans agrégateur)

Aucun intermédiaire ni commission : le client vire le montant sur le **numéro marchand** de l'agence puis envoie dans l'app la **capture d'écran** de la transaction (avec sa référence). L'admin vérifie la transaction sur le compte marchand et **confirme ou refuse** depuis la fiche de la livraison ; il peut aussi **valider directement** un paiement reçu autrement (espèces, virement vérifié). Un livreur ne peut être assigné qu'après confirmation.

Mise en service : *Admin › Réglages* › numéros marchands Flooz et/ou Mixx by Yas (au moins un), nom du compte et instructions éventuelles.

Contrôles : une même référence de transaction ne peut pas servir deux fois ; les captures sont privées (visibles uniquement par l'admin).

## Identité visuelle

Couleurs VOOM : jaune `#FFD700`, noir `#000000`, blanc. Le logo (moto stylisée formant « VOOM ») est dans :

| Fichier | Usage |
|---|---|
| `assets/images/voom_logo.svg` | Logo affiché dans l'app (splash, connexion, espace livreur) |
| `assets/images/voom_icon.png` (1024×1024) | Source des icônes Android / iOS |
| `backend/public/images/voom-logo.svg`, `voom-icon.svg` | Panneau admin et favicon |

Pour utiliser le fichier officiel de l'agence : remplacer ces fichiers (mêmes noms), puis régénérer les icônes avec `dart run flutter_launcher_icons`.

## Marketplace, packs et promos (panneau admin)

- **Sous-catégories** (*Marketplace › Sous-catégories*) : 6 onglets Agro créés au départ (Céréales & légumineuses, Légumes, Tubercules, Fruits, Œufs-volaille-poisson, Huiles & transformés), renommables, réordonnables ; affichés en **onglets verticaux** dans l'app.
- **Packs** (*Marketplace › + Nouveau pack*) : plusieurs produits + quantités, un prix ; affichés avec le badge PACK et leur contenu.
- **Promos** (*Promos*) : titre, message, image, produit lié, dates ; affichées en **bandeau défilant** sur l'accueil et envoyées en **notification push** à tous les clients (case à cocher ou bouton « Envoyer la notification »).
- **Heure limite** : le client indique « à livrer avant » ; affichée au livreur avec compte à rebours et dans l'admin (« EN RETARD » si dépassée).

## Notifications push (Firebase, gratuit sans carte bancaire)

Rappels aux livreurs (nouvelle course, livraison Express, heure limite proche ou dépassée — toutes les 10 min) et promos aux clients.

1. https://console.firebase.google.com › **Créer un projet** (plan Spark gratuit, aucune carte demandée).
2. **Ajouter une application Android**, nom de paquet `com.voomdelivery.app` › télécharger `google-services.json`.
3. GitHub › Settings › Secrets › Actions :
   - `GOOGLE_SERVICES_JSON` = contenu de `google-services.json` encodé en base64 (`base64 -w0 google-services.json`) ;
   - `CRON_SECRET` = la valeur générée par Render pour `CRON_SECRET` (service › Environment).
4. Firebase › Paramètres du projet › **Comptes de service** › « Générer une nouvelle clé privée » › encoder le JSON en base64 et le coller dans Render › `FIREBASE_CREDENTIALS`.
5. Relancer le build de l'APK (Actions › Build APK › Run workflow).

Sans ces réglages, l'application fonctionne normalement, sans notifications.

## Démarrage en local

### 1. Backend

Prérequis : PHP 8.3+, Composer.

```bash
cd backend
composer install
cp .env.example .env          # puis ajuster ADMIN_EMAIL / ADMIN_PASSWORD
php artisan key:generate
php artisan migrate --seed    # SQLite par défaut ; crée l'admin + données de démo
php artisan storage:link
php artisan serve --host=0.0.0.0 --port=8000
```

- Panneau admin : http://localhost:8000/admin (identifiants `ADMIN_EMAIL` / `ADMIN_PASSWORD` du `.env`).
- Comptes de démo (hors production) : client `client@voom.tg`, livreur `livreur@voom.tg`, mot de passe `password123`.
- Tests : `php artisan test`.

### 2. Application Flutter

Prérequis : Flutter 3.35+ ; sous Windows, activer le **Mode développeur** (requis pour les plugins).

1. Cartes : **OpenStreetMap** (`flutter_map`) et adresses via **Nominatim** — gratuits, sans clé ni carte bancaire.
   L'itinéraire du livreur ouvre l'application Google Maps du téléphone par un simple lien (gratuit, sans clé).
2. Notifications push (facultatif) : voir « Notifications push » ci-dessus.
3. Lancer :
   ```bash
   flutter pub get
   # Émulateur Android (backend sur la machine hôte) :
   flutter run
   # Téléphone réel sur le même Wi-Fi :
   flutter run --dart-define=API_BASE_URL=http://IP_DU_PC:8000/api/v1
   ```
   En build release, l'app utilise par défaut `https://voom-delivery-api.onrender.com/api/v1`.

Tests : `flutter test` · analyse : `flutter analyze`.

## Déploiement de l'API sur Render

1. Render › **New** › **Blueprint** › choisir ce dépôt : `render.yaml` crée le service web **`voom-delivery-api`** (Docker, dossier `backend/`) et la base PostgreSQL **`voom-delivery-db`**.
2. Renseigner les variables demandées : `ADMIN_EMAIL`, `ADMIN_PHONE`, `ADMIN_PASSWORD`.
3. Au démarrage, le conteneur exécute les migrations et crée/met à jour le compte admin.
4. URL de l'API : `https://voom-delivery-api.onrender.com/api/v1` · admin : `https://voom-delivery-api.onrender.com/admin`.

> ⚠️ Plan gratuit : le disque est éphémère (les captures de paiement et photos produits sont perdues au redéploiement) et la base PostgreSQL gratuite expire après 30 jours. Pour la production, passer en plan payant et activer le disque prévu (commenté) dans `render.yaml`.

## API (préfixe `/api/v1`, jeton `Authorization: Bearer …`)

| Méthode | Route | Rôle | Description |
|---|---|---|---|
| POST | `/register` | public | Inscription client |
| POST | `/login` | public | Connexion (`login` = email ou téléphone) |
| GET | `/me` · POST `/logout` | connecté | Profil · déconnexion |
| GET | `/products?category=shopping\|agro` | connecté | Marketplace |
| GET | `/payment-info` | connecté | Numéros marchands Flooz / Mixx |
| POST | `/deliveries/quote` | client | Estimation du prix |
| GET/POST | `/deliveries` | client | Mes livraisons · nouvelle demande |
| GET | `/deliveries/{id}` | client | Détail |
| POST | `/deliveries/{id}/payment` | client | Preuve de paiement (multipart, `screenshot`) |
| POST | `/deliveries/{id}/cancel` | client | Annulation (avant confirmation du paiement) |
| POST | `/deliveries/{id}/photos` | client | Photo d'un article (multipart, `photo`) |
| POST · DELETE | `/me/avatar` | connecté | Photo de profil (multipart, `photo`) · suppression |
| GET · POST | `/requests` | client | Discussions · envoi rapide (`photos[]`, `message`) |
| GET | `/requests/{id}` | client | Discussion + livraison programmée |
| POST | `/requests/{id}/messages` | client | Message : `body`, `photo` ou `lat`/`lng` |
| GET | `/courier/deliveries[?scope=history]` | livreur | Livraisons assignées |
| GET | `/courier/deliveries/{id}` | livreur | Détail + coordonnées A/B |
| POST | `/courier/deliveries/{id}/status` | livreur | `picked_up` puis `delivered` |
