#!/usr/bin/env bash
set -euo pipefail

# ↑↑ CONFIGURAZIONE aaPanel ↑↑
PANEL_URL="https://tuo-server:8888"
PANEL_USER="admin"
PANEL_PASS="password_aaPanel"
APITOKEN=""

# ↑↑ PARAMETRI FIGLIO ↑↑
PROJECT_SLUG="project_slug"
DOMAIN="wyrmrest.com"                  # stesso dominio
PREFIX_PATH="/${PROJECT_SLUG}"         # es. /ristorante
ROOT_DIR="/www/wwwroot/${PROJECT_SLUG}/frontend/dist"
PHP_VERSION="php-82"

# ↑↑ CONFIGURAZIONE LOCAL BUILD ↑↑
FRONT_SRC="$HOME/portfolio/${PROJECT_SLUG}/frontend"
BACK_SRC="$HOME/portfolio/${PROJECT_SLUG}/backend"
PROD_FE="/www/wwwroot/${PROJECT_SLUG}/frontend/dist"
PROD_BE="/www/wwwroot/${PROJECT_SLUG}/backend"

PHP_FPM_SERVICE="php8.1-fpm"

# 1) Login
JSON=$(curl -ks "$PANEL_URL/api/login" -d "username=$PANEL_USER&password=$PANEL_PASS")
APITOKEN=$(echo "$JSON" | grep -oP '(?<="token":").*?(?=")')
[ -n "$APITOKEN" ] || { echo "Login fallito"; exit 1; }

# 2) Crea il sito figlio come “sub-dir” del dominio principale
curl -ks "$PANEL_URL/api/site?action=AddSite" \
  -H "Authorization: Bearer $APITOKEN" \
  -d "type=4" \                            # tipo “subdir”
  -d "domain=$DOMAIN" \
  -d "path=$ROOT_DIR" \
  -d "dirname=$PROJECT_SLUG" \             # nome della cartella
  -d "ftp=0" \
  -d "sql=0" \
  -d "version=$PHP_VERSION" >/dev/null

# 3) Build e copia frontend
cd "$FRONT_SRC"
npm ci
ng build --configuration=production
mkdir -p "$PROD_FE"
rm -rf "$PROD_FE"/*
cp -r dist/* "$PROD_FE/"

# 4) Composer & rsync backend
cd "$BACK_SRC"
composer install --no-dev --optimize-autoloader
php artisan config:cache && php artisan route:cache
rsync -av --delete --exclude='.git' "$BACK_SRC/" "$PROD_BE/"

# 5) Migrazioni, permessi e reload
cd "$PROD_BE"
php artisan migrate --force
chown -R www-data:www-data storage bootstrap/cache

sudo systemctl reload "$PHP_FPM_SERVICE"
sudo systemctl reload nginx

echo "✅ Deploy figlio \'$PROJECT_SLUG\' completato!"
