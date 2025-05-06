#!/bin/bash

# enable-nginx-env.sh
# Prepara la struttura di NGINX per ambienti DEV e PROD
# Crea le cartelle necessarie e copia proxy_params.conf

set -e

# Percorsi di base
DEV_BASE="/www/wwwroot/dev/nginx"
PROD_BASE="/www/server/nginx/conf"

# Elenco directory da creare
DIRS=(
  "conf.d"
  "sites-available/dev"
  "sites-available/prod"
  "sites-enabled/dev"
  "sites-enabled/prod"
)

# Funzione di copia proxy_params.conf se presente
copy_proxy() {
  local src="$1/conf.d/proxy_params.conf"
  local dst_base="$2"
  if [[ -f "$src" ]]; then
    sudo cp "$src" "$dst_base/conf.d/proxy_params.conf"
    echo "  📄 Copiato proxy_params.conf in $dst_base/conf.d"
  fi
}

# Ciclo su DEV e PROD
for BASE in "$DEV_BASE" "$PROD_BASE"; do
  echo "📂 Configuro NGINX in $BASE"
  for D in "${DIRS[@]}"; do
    PATH_DIR="$BASE/$D"
    if [ ! -d "$PATH_DIR" ]; then
      sudo mkdir -p "$PATH_DIR"
      echo "  ➕ Creato $PATH_DIR"
    fi
  done
  copy_proxy "$BASE"
done

echo "✅ Struttura NGINX per DEV e PROD pronta."
