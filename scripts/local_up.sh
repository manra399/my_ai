#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] && export $(grep -v '^#' .env | xargs) || true
docker compose -f compose/docker-compose.yml up -d
echo "Open WebUI: http://localhost:${WEBUI_PORT:-3000}"
echo "Ollama API: http://localhost:11434"
