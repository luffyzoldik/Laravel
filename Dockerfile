# ==========================================
# Étape 1 : Builder (Dépendances Composer)
# ==========================================
FROM php:8.2-cli AS builder

# Installation des outils système nécessaires (git, unzip, libsqlite3)
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Installation de Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Argument pour passer l'URL du dépôt lors du build (ex: docker build --build-arg REPO_URL=...)
ARG REPO_URL
RUN git clone ${REPO_URL} .

# Installation des dépendances PHP pour la production (sans dev-dependencies)
RUN composer install --no-dev --optimize-autoloader --no-interaction --prefer-dist

# ==========================================
# Étape 2 : Image de Production (Runtime Apache)
# ==========================================
FROM php:8.2-apache

# Installation des extensions PHP requises (pdo_sqlite, zip) et utilitaires
RUN apt-get update && apt-get install -y \
    libsqlite3-dev \
    libzip-dev \
    zip \
    && docker-php-ext-install pdo_sqlite pdo_mysql zip \
    && rm -rf /var/lib/apt/lists/*

# Activation du module rewrite d'Apache (nécessaire pour le routage Laravel)
RUN a2enmod rewrite

# Modification du DocumentRoot d'Apache pour pointer vers /var/www/html/public
ENV APACHE_DOCUMENT_ROOT /var/www/html/public
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/conf-available/*.conf

WORKDIR /var/www/html

# Copie du projet depuis le builder
COPY --from=builder /app /var/www/html

# ==========================================
# Configuration de la base SQLite & Production
# ==========================================

# 1. Création du fichier SQLite et configuration du stockage
RUN mkdir -p database storage/framework/{sessions,views,cache} \
    && touch database/database.sqlite

# 2. Configuration des variables d'environnement de prod (Bonus)
ENV APP_ENV=production \
    APP_DEBUG=false \
    DB_CONNECTION=sqlite \
    DB_DATABASE=/var/www/html/database/database.sqlite

# 3. Permissions pour Apache (www-data) sur storage, bootstrap/cache et la base SQLite
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache /var/www/html/database

# 4. Optimisations Laravel pour la production (Bonus)
RUN php artisan config:cache \
    && php artisan route:cache \
    && php artisan view:cache \
    && php artisan migrate --force

EXPOSE 80

CMD ["apache2-foreground"]
