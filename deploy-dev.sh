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

# --- Rimuovo struttura esistente ---
echo "🧹 Rimuovo struttura deploy esistente..."
sudo rm -rf ./deploy

# --- Ricreo struttura iniziale NGINX ---
echo "📁 Ricreo struttura iniziale NGINX..."
sudo ./sima-init-structure.sh -dev "$PROJECT"

# --- Verifica file delle porte ---
PORTS_FILE="./deploy/assigned_ports.env"
if [[ ! -f "$PORTS_FILE" ]]; then
  echo "❌ File porte non trovato: $PORTS_FILE"
  exit 1
fi
source "$PORTS_FILE"
export BACKEND_PORT="$BACK_PORT"

# --- Build Backend in ambiente DEV ---
echo "🔧 Build backend in ambiente DEV..."
sudo ./simb-build-backend.sh -dev "$PROJECT"

# --- Build Frontend in ambiente DEV ---
echo "🔨 Build frontend in ambiente DEV..."
sudo ./simc-build-frontend.sh -dev "$PROJECT"

# --- Generazione configurazione NGINX simulata ---
echo -e "\n⚙️ Genero configurazione NGINX simulata..."
sudo ./simd-nginx-deploy.sh -dev "$PROJECT"

# --- Applicazione della configurazione come reale ---
echo "🚀 Applico la simulazione come configurazione reale..."
sudo ./sime-deploy-apply.sh -dev "$PROJECT"

# --- Finalizzazione ---
echo "✅ Deploy completo per '$PROJECT' in ambiente DEV"
