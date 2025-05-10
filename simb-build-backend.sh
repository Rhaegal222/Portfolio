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

# Verifica se è stato specificato un progetto
if [ -z "$1" ]; then
  echo "❌ Specificare nome progetto"
  exit 1
else
  PROJECT="$1"
  shift
fi 

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_PATH=$(realpath "$PROJECT")

# Controlli preliminari sull’input
if [ ! -d "$PROJECT_PATH" ]; then
  echo "❌ La cartella del progetto non esiste: $PROJECT_PATH"
  exit 1
fi

# Ora cerchiamo la cartella _backend per verificare la presenza di composer.json
BACKEND_DIR=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_backend")

if [ -n "$BACKEND_DIR" ]; then
  PROJECT_NAME=$(basename "$BACKEND_DIR" | cut -d'_' -f1)
else
  echo "❌ Nessuna cartella *_backend trovata in $PROJECT_PATH"
  exit 1
fi

# Verifica che il progetto Laravel (composer.json) sia presente nella cartella _backend
if [ ! -f "$BACKEND_DIR/composer.json" ]; then
  echo "❌ Non sembra un progetto Laravel (manca composer.json) in $BACKEND_DIR"
  exit 1
fi

# Riepilogo
echo "ℹ️  Modalità di deploy: $MODE"
echo "ℹ️  Nome progetto:     $PROJECT_NAME"
echo "ℹ️  Percorso progetto:  $PROJECT_PATH"
echo "ℹ️  Backend trovato:    $BACKEND_DIR"

# Conferma per procedere
read -rp $'\e[1;33m⚠️  Confermi di procedere con il deploy? [\e[1;32my/\e[1;31mN\e[0m] (default N): ' CONFIRM
CONFIRM=${CONFIRM:-n}
CONFIRM=${CONFIRM,,}
if [[ "$CONFIRM" != "y" ]]; then
  echo "⏹️  Operazione annullata"
  exit 1
fi

# 📌 Chiedo se è progetto principale? (default N)
read -rp $'\e[1;33m📌 È il progetto principale? [\e[1;32my/\e[1;31mN\e[0m] (default N): ' IS_MAIN
IS_MAIN=${IS_MAIN:-n}     # default n
IS_MAIN=${IS_MAIN,,}      # lowercase

if [[ "$IS_MAIN" == "y" ]]; then
  sudo rm -rf "$SCRIPT_DIR/deploy/www/wwwroot/$MODE/apps"
  BASE_DIR="$SCRIPT_DIR/deploy/www/wwwroot/$MODE/$PROJECT_NAME"
else
  BASE_DIR="$SCRIPT_DIR/deploy/www/wwwroot/$MODE/apps/$PROJECT_NAME"
fi

BACKEND_DEST="$BASE_DIR/backend"

echo "⚙️ Deploy backend: $PROJECT_NAME -> $BACKEND_DEST"

# Copia sorgente
rm -rf "$BACKEND_DEST"
mkdir -p "$BACKEND_DEST"
rsync -a --exclude .env --exclude vendor "$BACKEND_DIR"/ "$BACKEND_DEST"/

# Imposta .env
if [ -f "$BACKEND_DIR/.env.prod" ] && [[ "$MODE" == "prod" ]]; then
  cp "$BACKEND_DIR/.env.prod" "$BACKEND_DEST/.env"
elif [ -f "$BACKEND_DIR/.env.example" ]; then
  cp "$BACKEND_DIR/.env.example" "$BACKEND_DEST/.env"
fi

# Installazione
cd "$BACKEND_DEST"
composer install --no-dev --optimize-autoloader --no-interaction
php artisan key:generate --ansi --quiet

# Permessi
chown -R www:www storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

echo "✅ Backend pronto in $BACKEND_DEST"
