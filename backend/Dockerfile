# Image de production de l'API S-Delivery (Render, runtime Docker).
FROM php:8.4-apache

# gd (JPEG / PNG / WebP) : réduction des photos à l'envoi ; exif : sens des photos de téléphone.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq-dev libzip-dev libjpeg62-turbo-dev libpng-dev libwebp-dev unzip git \
    && docker-php-ext-configure gd --with-jpeg --with-webp \
    && docker-php-ext-install pdo_pgsql zip opcache gd exif \
    && a2enmod rewrite headers \
    && rm -rf /var/lib/apt/lists/*

# Apache sert le dossier public/ de Laravel.
# Envois : 8 Mo par fichier, 40 Mo par requête (jusqu'à 6 photos d'un coup) ; 256 Mo de mémoire suffisent à GD.
ENV APACHE_DOCUMENT_ROOT=/var/www/html/public
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
    && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf \
    && printf 'upload_max_filesize=8M\npost_max_size=40M\nmax_file_uploads=10\nmemory_limit=256M\nexpose_php=Off\n' > /usr/local/etc/php/conf.d/sdelivery.ini \
    && cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Dépendances d'abord, pour profiter du cache Docker.
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction

COPY . .
RUN composer dump-autoload --optimize --no-dev \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod +x docker/entrypoint.sh

ENV PORT=10000
EXPOSE 10000

ENTRYPOINT ["docker/entrypoint.sh"]
CMD ["apache2-foreground"]
