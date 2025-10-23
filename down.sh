#!/usr/bin/env bash
set -e
echo "🧹 Removendo containers e volumes (LocalStack + dados persistidos)..."
docker compose down -v
echo "✅ Finalizado."
