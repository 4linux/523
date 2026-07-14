#!/usr/bin/env bash
# DevOps Essentials — Remove toda a stack do laboratório
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC}  $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
info() { echo -e "⏳  $1"; }

CLUSTER_NAME="devops-lab"

echo -e "\n🗑  Removendo laboratório DevOps...\n"

# Remove o cluster Kind (inclui todos os deployments, serviços e volumes do cluster)
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  info "Removendo cluster Kind '${CLUSTER_NAME}'..."
  kind delete cluster --name "$CLUSTER_NAME"
  ok "Cluster removido"
else
  warn "Cluster '${CLUSTER_NAME}' não encontrado"
fi

# Remove o repositório clonado localmente durante o lab
if [[ -d /tmp/devops-lab-repo ]]; then
  rm -rf /tmp/devops-lab-repo
  ok "Repositório temporário removido"
fi

# Remove arquivos temporários do setup
rm -f /tmp/kind-devops-lab.yaml

echo ""
ok "Teardown concluído. Todos os recursos do laboratório foram removidos."
echo ""
