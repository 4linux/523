#!/usr/bin/env bash
# diagnose.sh — AIOps: diagnóstico de pods Kubernetes via OpenRouter
#
# Uso:
#   kubectl logs <pod> -n <namespace> | bash diagnose.sh
#   bash diagnose.sh <pod> -n <namespace>
#   bash diagnose.sh <pod> -n <namespace> --previous
#
# Configuração:
#   export OPENROUTER_API_KEY="sk-or-..."
#   export OPENROUTER_MODEL="mistralai/mistral-7b-instruct:free"  # opcional

set -euo pipefail

MODEL="${OPENROUTER_MODEL:-mistralai/mistral-7b-instruct:free}"
API_URL="https://openrouter.ai/api/v1/chat/completions"

# ── Validações ────────────────────────────────────────────────────────────────

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
  echo ""
  echo "Erro: variável OPENROUTER_API_KEY não definida."
  echo ""
  echo "  1. Crie sua conta em https://openrouter.ai"
  echo "  2. Gere uma chave em https://openrouter.ai/keys"
  echo "  3. Execute: export OPENROUTER_API_KEY='sk-or-...'"
  echo ""
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Erro: jq não encontrado. Instale com: apt-get install -y jq"
  exit 1
fi

# ── Coleta os logs ────────────────────────────────────────────────────────────

if [[ -p /dev/stdin ]]; then
  LOGS=$(cat)
elif [[ $# -gt 0 ]]; then
  echo "Coletando logs do pod..."
  LOGS=$(kubectl logs "$@" 2>&1 || true)
else
  echo ""
  echo "Uso:"
  echo "  kubectl logs <pod> -n <namespace> | bash diagnose.sh"
  echo "  bash diagnose.sh <pod> -n <namespace>"
  echo ""
  exit 1
fi

if [[ -z "$LOGS" ]]; then
  echo "Nenhum log encontrado."
  exit 1
fi

# ── Monta o prompt e chama a API ──────────────────────────────────────────────

PAYLOAD=$(jq -n \
  --arg model  "$MODEL" \
  --arg logs   "$LOGS" \
  '{
    model: $model,
    max_tokens: 600,
    messages: [{
      role: "user",
      content: ("Você é um especialista em Kubernetes e DevOps.\nAnalise os logs abaixo e responda em português:\n\n1. Qual é o problema?\n2. Qual é a causa mais provável?\n3. Como corrigir?\n\nSeja direto e objetivo.\n\nLOGS:\n" + $logs)
    }]
  }')

echo ""
echo "Modelo : $MODEL"
echo "────────────────────────────────────────────"
echo ""

curl -s \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://4linux.com.br" \
  -H "X-Title: DevOps Essentials Lab" \
  -d "$PAYLOAD" \
  "$API_URL" \
  | jq -r '.choices[0].message.content // ("Erro: " + (.error.message // "resposta inesperada da API"))'

echo ""
