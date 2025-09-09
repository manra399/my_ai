#!/usr/bin/env bash
set -euo pipefail
if [[ "$#" -eq 0 ]]; then
  echo "Usage: $0 model1 [model2 ...]"
  exit 1
fi
CID=$(docker ps --format '{{.ID}} {{.Image}} {{.Names}}' | awk '/ollama\/ollama/ {print $1; exit}')
if [[ -z "$CID" ]]; then
  echo "Could not find running Ollama container."
  exit 1
fi
for m in "$@"; do
  echo "Pulling $m..."
  docker exec -i "$CID" ollama pull "$m"
done
