#!/bin/bash

# simb-build-backend.sh
# Prepara il backend Laravel per il deploy

set -e

# 📍 Parametri
if [[ "$1" != "-dev" && "$1" != "-prod" ]]; then
  echo "❌ Uso corretto: $0 -dev|-prod <percorso_progetto>"
  exit 1
fi
MODE=${1#-}
shift

if [ -z "$1" ]; then
  echo "❌ Specificare percorso progetto"
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_PATH=$(realpath "$1")
PROJECT_NAME=$(basename "$PROJECT_PATH")

BACKEND_SRC=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_backend")
BACKEND_DEST="$SCRIPT_DIR/deploy/www/wwwroot/$MODE/$PROJECT_NAME/backend"

echo "⚙️ Deploy backend: $PROJECT_NAME"

# Copia sorgente
rm -rf "$BACKEND_DEST"
mkdir -p "$BACKEND_DEST"
rsync -a --exclude .env --exclude vendor "$BACKEND_SRC/" "$BACKEND_DEST/"

# Imposta .env
if [ -f "$BACKEND_SRC/.env.prod" ]; then
  cp "$BACKEND_SRC/.env.prod" "$BACKEND_DEST/.env"
elif [ -f "$BACKEND_SRC/.env.example" ]; then
  cp "$BACKEND_SRC/.env.example" "$BACKEND_DEST/.env"
fi

# Installazione
cd "$BACKEND_DEST"
composer install --no-dev --optimize-autoloader --no-interaction
php artisan key:generate --ansi --quiet

# Permessi
chown -R www:www storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

echo "✅ Backend pronto in $BACKEND_DEST"
