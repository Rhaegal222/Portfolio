#!/bin/bash

# deploy-dev.sh
# 1. Cancella e ricrea la struttura deploy
# 2. Builda frontend e backend separatamente
# 3. Crea i virtual host NGINX (simulati)
# 4. Li sincronizza nel server reale

set -euo pipefail

# --- Verifica parametro progetto ---
if [[ -z "${1:-}" ]]; then
  echo "❌ Uso corretto: $0 <nome_progetto>"
  exit 1
fi
PROJECT="$1"

echo "🧹 Rimuovo struttura deploy esistente..."
sudo rm -rf ./deploy

echo "📁 Ricreo struttura iniziale NGINX..."
sudo ./sima-init-structure.sh "$PROJECT"

PORTS_FILE="./deploy/assigned_ports.env"
if [[ ! -f "$PORTS_FILE" ]]; then
  echo "❌ File porte non trovato: $PORTS_FILE"
  exit 1
fi

source "$PORTS_FILE"
export BACKEND_PORT="$BACK_PORT"

echo "🔧 Build backend in ambiente DEV..."
sudo ./simb-build-backend.sh -dev "$PROJECT"

echo "🔨 Build frontend in ambiente DEV..."
sudo ./simc-build-frontend.sh -dev "$PROJECT"

echo "⚙️  Genero configurazione NGINX simulata..."
sudo ./simd-nginx-deploy.sh -dev

echo "🚀 Applico la simulazione come configurazione reale..."
sudo ./sim-to-live.sh -dev

echo "✅ Deploy completo per '$PROJECT' in ambiente DEV"
