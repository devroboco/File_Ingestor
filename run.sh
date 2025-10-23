#!/usr/bin/env bash
set -e

echo "🚀 Subindo LocalStack..."
docker compose up -d

echo "⏳ Aguardando LocalStack iniciar..."
# imprime logs a partir de "Ready." quando disponível
until docker logs localstack 2>&1 | grep -q "Ready."; do sleep 2; done

echo "⚙️  Provisionando recursos (buckets, tabela, lambdas, API)..."
docker exec -it localstack bash -lc "/scripts/setup_resources.sh"

echo "✅ Ambiente pronto!"
echo
echo "Dica: para testar e gerar outputs p/ screenshots, rode:"
echo "docker exec -it localstack bash -lc \"/scripts/test_flow.sh\""
