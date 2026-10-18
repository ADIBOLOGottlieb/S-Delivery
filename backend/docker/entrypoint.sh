#!/bin/sh
set -e

# Render fournit le port d'écoute dans $PORT.
sed -i "s/Listen 80$/Listen ${PORT:-10000}/" /etc/apache2/ports.conf
sed -i "s/<VirtualHost \*:80>/<VirtualHost *:${PORT:-10000}>/" /etc/apache2/sites-available/000-default.conf

# Render « generateValue » produit une clé base64 de 256 bits sans le préfixe attendu par Laravel.
case "$APP_KEY" in
  base64:*) ;;
  "") echo "APP_KEY manquante" >&2; exit 1 ;;
  *) export APP_KEY="base64:$APP_KEY" ;;
esac

mkdir -p storage/app/public storage/app/private storage/framework/cache storage/framework/sessions storage/framework/views storage/logs
chown -R www-data:www-data storage bootstrap/cache

php artisan storage:link --force >/dev/null 2>&1 || true
# Une configuration en cache d'un démarrage précédent masquerait les variables d'environnement lues par les seeders.
php artisan config:clear >/dev/null 2>&1 || true
php artisan migrate --force
# Compte admin (ADMIN_EMAIL / ADMIN_PASSWORD) et catalogue de départ, sans données démo en production.
# Un échec ici ne doit pas empêcher l'API de démarrer : on le journalise et on continue.
if ! php artisan db:seed --force; then
  echo "AVERTISSEMENT : db:seed a échoué (voir ci-dessus) ; le serveur démarre quand même." >&2
fi
php artisan config:cache
php artisan route:cache
php artisan view:cache

exec "$@"
