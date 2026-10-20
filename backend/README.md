# S-Delivery — API & administration

API REST (Laravel 13 + Sanctum) et panneau d'administration web de S-Delivery.
Voir le [README principal](../README.md) pour le fonctionnement global, l'installation et le déploiement Render.

## Organisation

| Élément | Emplacement |
|---|---|
| Règles métier (statuts, assignation, transitions livreur) | `app/Models/Delivery.php` |
| Calcul du prix | `app/Services/PricingService.php` |
| API mobile | `app/Http/Controllers/Api/*`, `routes/api.php` |
| Panneau admin (Blade + Tailwind CDN) | `app/Http/Controllers/Admin/*`, `resources/views/admin`, `routes/web.php` |
| Réglages (numéros marchands, tarifs) | table `settings`, `app/Models/Setting.php` |
| Restriction par rôle | `app/Http/Middleware/EnsureRole.php` (alias `role`) |

## Statuts

- Livraison : `pending` → `assigned` → `picked_up` → `delivered` (ou `cancelled`).
- Paiement : `unpaid` → `submitted` → `verified` | `rejected` (le client peut renvoyer une preuve après un refus).

Les captures de paiement sont stockées sur le disque privé (`storage/app/private/payments`) et ne sont servies qu'aux admins.

## Commandes utiles

```bash
php artisan migrate --seed   # schéma + admin (+ démo hors production)
php artisan test             # tests de bout en bout du parcours
php artisan serve            # http://localhost:8000/admin
```
