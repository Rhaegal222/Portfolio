#!/bin/bash

# simb-build-backend.sh
# Prepara il backend Laravel per il deploy

set -e

# 📍 Parametri
echo -e "\n🔍  \e[1;33mSTEP 0:\e[0m Verifico modalità di esecuzione: \e[1;32m$1\e[0m"
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
  echo -e "\n  ➤  Progetto specificato: \e[1;32m$PROJECT\e[0m"
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
echo -e "\n🔍  \e[1;33mSTEP 1:\e[0m Cerco cartella *_backend in $PROJECT_PATH"
BACKEND_DIR=$(find "$PROJECT_PATH" -maxdepth 1 -type d -name "*_backend")

if [ -n "$BACKEND_DIR" ]; then
  PROJECT_NAME=$(basename "$BACKEND_DIR" | cut -d'_' -f1)
else
  echo "❌ Nessuna cartella *_backend trovata in $PROJECT_PATH"
  exit 1
fi

# Riepilogo
echo -e "\nℹ️   \e[1;32mRiepilogo del progetto\e[0m\n"
echo -e "  ➤  Modalità di deploy: \e[1;33m$MODE\e[0m"
echo -e "  ➤  Nome progetto:      \e[1;33m$PROJECT_NAME\e[0m"
echo -e "  ➤  Percorso progetto:  \e[1;33m$PROJECT_PATH\e[0m"
echo -e "  ➤  Backend trovato:   \e[1;33m$BACKEND_DIR\e[0m"

# Verifica che il progetto Laravel (composer.json) sia presente nella cartella _backend
echo -e "\n🔍  \e[1;33mSTEP 2:\e[0m Verifico presenza composer.json in $BACKEND_DIR"
if [ ! -f "$BACKEND_DIR/composer.json" ]; then
  echo "❌ Non sembra un progetto Laravel (manca composer.json) in $BACKEND_DIR"
  exit 1
fi

# Conferma per procedere
read -rp $'\n\e[1;33m⚠️   Confermi di procedere con il deploy? [\e[1;32my/\e[1;31mN\e[0m] (default N): ' CONFIRM
CONFIRM=${CONFIRM:-n}
CONFIRM=${CONFIRM,,}
if [[ "$CONFIRM" != "y" ]]; then
  echo "⏹️  Operazione annullata"
  exit 1
fi

# 📌 Chiedo se è progetto principale? (default N)
read -rp $'\n\e[1;33m📌  È il progetto principale? [\e[1;32my/\e[1;31mN\e[0m] (default N): ' IS_MAIN
IS_MAIN=${IS_MAIN:-n}     # default n
IS_MAIN=${IS_MAIN,,}      # lowercase

if [[ "$IS_MAIN" == "y" ]]; then
  sudo rm -rf "$SCRIPT_DIR/deploy/www/wwwroot/$MODE/apps"
  BASE_DIR="$SCRIPT_DIR/deploy/www/wwwroot/$MODE/$PROJECT_NAME"
else
  BASE_DIR="$SCRIPT_DIR/deploy/www/wwwroot/$MODE/apps/$PROJECT_NAME"
fi

BACKEND_DEST="$BASE_DIR/backend"

# Copia sorgente
echo -e "\n⚙️   \e[1;33mSTEP 3:\e[0m Deploy backend: \e[1;32m$PROJECT_NAME\e[0m -> \e[1;32m$BACKEND_DEST\e[0m"
rm -rf "$BACKEND_DEST"
mkdir -p "$BACKEND_DEST"
rsync -a --exclude .env --exclude vendor "$BACKEND_DIR"/ "$BACKEND_DEST"/

echo -e "\n🔧  \e[1;33mSTEP 3.1:\e[0m Copia file di configurazione"
if [ -f "$BACKEND_DIR/.env.prod" ] && [[ "$MODE" == "prod" ]]; then
  cp "$BACKEND_DIR/.env.prod" "$BACKEND_DEST/.env"
elif [ -f "$BACKEND_DIR/.env.example" ]; then
  cp "$BACKEND_DIR/.env.example" "$BACKEND_DEST/.env"
fi

echo -e "\n📦  \e[1;33mSTEP 3.2:\e[0m Installazione dipendenze Laravel e generazione chiave applicativa"
cd "$BACKEND_DEST"
composer install --no-dev --optimize-autoloader --no-interaction
php artisan key:generate --ansi --quiet

echo -e "\n🔐   \e[1;33mSTEP 3.3:\e[0m Imposto permessi su storage e bootstrap/cache"
chown -R www:www storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

echo -e "\n✅   Backend pronto in \e[1;32m$BACKEND_DEST\e[0m"
