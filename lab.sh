#!/usr/bin/env bash
# DevOps Essentials — Laboratório guiado passo a passo
# Execute após o setup.sh. Cada passo pode ser reexecutado individualmente.
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'
ok()    { echo -e "${GREEN}✓${NC}  $1"; }
info()  { echo -e "${BLUE}⏳${NC}  $1"; }
step()  { echo -e "\n${CYAN}${BOLD}[ Passo $1 ]${NC} $2\n"; }
pause() { echo -e "\n${YELLOW}→  Pressione ENTER para continuar...${NC}"; read -r; }

GITEA_URL="http://localhost:3000"
GITEA_ADMIN="gitadmin"
GITEA_PASS="gitadmin123"
GITEA_REPO="devops-lab"
APP_URL="http://localhost:9090"
ARGOCD_URL="http://localhost:8080"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Passo 0: Build e load da imagem ──────────────────────────────────────────
passo_0_build_imagem() {
  step "0" "Build da imagem Docker e carregamento no cluster Kind"

  echo "  O Kind não tem acesso ao Docker Hub durante o lab."
  echo "  Vamos buildar a imagem localmente e carregá-la diretamente no cluster."
  echo ""

  info "Buildando imagem devops-app:latest..."
  docker build -t devops-app:latest "${SCRIPT_DIR}/app/"
  ok "Imagem construída"

  info "Carregando imagem no cluster Kind..."
  kind load docker-image devops-app:latest --name devops-lab
  ok "Imagem carregada no cluster"

  pause
}

# ── Passo 1: Push dos manifests para o Gitea ─────────────────────────────────
passo_1_push_manifests() {
  step "1" "Push dos manifests Kubernetes para o Gitea"

  echo "  O ArgoCD vai monitorar esse repositório e aplicar qualquer mudança"
  echo "  automaticamente no cluster. Esse é o ciclo básico do GitOps."
  echo ""

  local repo_dir="/tmp/devops-lab-repo"
  rm -rf "$repo_dir"

  info "Clonando repositório do Gitea..."
  git clone "http://${GITEA_ADMIN}:${GITEA_PASS}@localhost:3000/${GITEA_ADMIN}/${GITEA_REPO}.git" "$repo_dir"

  info "Copiando manifests..."
  cp -r "${SCRIPT_DIR}/k8s" "$repo_dir/"

  cd "$repo_dir"
  git config user.email "aluno@devops.local"
  git config user.name  "Aluno DevOps"
  git add k8s/
  git commit -m "feat: adiciona manifests iniciais da aplicação Flask"
  git push origin main

  ok "Manifests enviados para: ${GITEA_URL}/${GITEA_ADMIN}/${GITEA_REPO}"
  echo ""
  echo "  Abra no browser: ${GITEA_URL}/${GITEA_ADMIN}/${GITEA_REPO}/src/branch/main/k8s"

  pause
}

# ── Passo 2: Aplicar Application no ArgoCD ───────────────────────────────────
passo_2_argocd_application() {
  step "2" "Registrar a Application no ArgoCD"

  echo "  O arquivo argocd/application.yaml diz ao ArgoCD:"
  echo "    - Qual repositório monitorar (Gitea)"
  echo "    - Em qual namespace aplicar os manifests"
  echo "    - Que o sync deve ser automático (auto-sync + self-heal)"
  echo ""

  kubectl apply -f "${SCRIPT_DIR}/argocd/application.yaml"
  ok "Application 'devops-app' registrada no ArgoCD"

  echo ""
  echo "  Abra a UI do ArgoCD: ${ARGOCD_URL}"
  echo "  Usuário: admin"
  echo "  Senha: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"

  pause
}

# ── Passo 3: Observar o sync ──────────────────────────────────────────────────
passo_3_observar_sync() {
  step "3" "Observar o ArgoCD sincronizando"

  echo "  O ArgoCD detectou o repositório e vai criar os recursos no cluster."
  echo "  Aguarde os pods ficarem Running..."
  echo ""
  echo "  (Ctrl+C para interromper o watch quando os pods estiverem Running)"
  echo ""

  kubectl get pods -n default -w &
  local watch_pid=$!

  # Aguarda até o pod da app ficar pronto (máx 2 minutos)
  local attempts=0
  until kubectl get pods -n default -l app=devops-app --field-selector=status.phase=Running 2>/dev/null | grep -q "Running"; do
    [[ $attempts -ge 24 ]] && break
    sleep 5
    (( attempts++ ))
  done

  kill $watch_pid 2>/dev/null || true
  echo ""

  kubectl get pods,svc -n default
  ok "Recursos criados pelo ArgoCD"

  pause
}

# ── Passo 4: Testar a aplicação ───────────────────────────────────────────────
passo_4_testar_app() {
  step "4" "Testar os endpoints da aplicação"

  echo "  Testando os 3 endpoints da aplicação Flask..."
  echo ""

  echo -e "  ${CYAN}GET /${NC}"
  curl -s "${APP_URL}/" && echo ""
  echo ""

  echo -e "  ${CYAN}GET /health${NC}"
  curl -s "${APP_URL}/health" | python3 -m json.tool 2>/dev/null || curl -s "${APP_URL}/health"
  echo ""

  echo -e "  ${CYAN}GET /bucket${NC}  (lista buckets S3 do Floci)"
  curl -s "${APP_URL}/bucket" | python3 -m json.tool 2>/dev/null || curl -s "${APP_URL}/bucket"
  echo ""

  ok "Endpoints respondendo"

  pause
}

# ── Passo 5: GitOps na prática — escalar para 3 réplicas ─────────────────────
passo_5_escalar() {
  step "5" "GitOps na prática: escalar de 1 para 3 réplicas"

  echo "  A regra do GitOps: qualquer mudança passa pelo Git."
  echo "  Vamos editar o deployment.yaml, fazer commit e observar"
  echo "  o ArgoCD aplicar a mudança automaticamente."
  echo ""

  local repo_dir="/tmp/devops-lab-repo"
  cd "$repo_dir"
  git pull origin main

  info "Alterando replicas de 1 para 3..."
  # Substitui apenas a linha de replicas para não depender de editor
  sed -i.bak 's/  replicas: 1/  replicas: 3/' k8s/deployment.yaml
  rm -f k8s/deployment.yaml.bak

  git add k8s/deployment.yaml
  git commit -m "scale: aumenta réplicas da app para 3"
  git push origin main

  ok "Commit enviado. Observando o ArgoCD sincronizar..."
  echo ""
  echo "  (O ArgoCD tem polling de 3 minutos por padrão. Para forçar sync imediato:"
  echo "   kubectl -n argocd app sync devops-app)"
  echo ""

  # Força sync imediato se o CLI do ArgoCD estiver disponível
  if command -v argocd &>/dev/null; then
    argocd app sync devops-app --server localhost:8080 --insecure --auth-token "" 2>/dev/null || true
  fi

  echo "  Aguardando rollout..."
  kubectl rollout status deployment/devops-app -n default --timeout=3m
  echo ""
  kubectl get pods -n default -l app=devops-app

  ok "3 réplicas rodando — mudança aplicada via GitOps"

  pause
}

# ── Passo 6: Rollback via git revert ─────────────────────────────────────────
passo_6_rollback() {
  step "6" "Rollback: revertendo para 1 réplica via git revert"

  echo "  No GitOps, um rollback não é um comando kubectl — é um commit."
  echo "  O histórico do Git é a fonte da verdade. Revertemos o commit"
  echo "  anterior e o ArgoCD restaura o estado anterior automaticamente."
  echo ""

  local repo_dir="/tmp/devops-lab-repo"
  cd "$repo_dir"
  git pull origin main

  info "Revertendo o último commit (scale para 3 réplicas)..."
  git revert HEAD --no-edit
  git push origin main

  ok "git revert executado. Observando rollback automático..."
  echo ""

  if command -v argocd &>/dev/null; then
    argocd app sync devops-app --server localhost:8080 --insecure 2>/dev/null || true
  fi

  kubectl rollout status deployment/devops-app -n default --timeout=3m
  echo ""
  kubectl get pods -n default -l app=devops-app

  ok "Rollback concluído — 1 réplica restaurada"
  echo ""
  echo "  Observe o log do Git para ver o histórico completo:"
  git log --oneline -5

  pause
}

# ── Sumário final ─────────────────────────────────────────────────────────────
sumario_final() {
  cat <<EOF

  ${GREEN}${BOLD}🎉  Laboratório concluído!${NC}
  ══════════════════════════════════════════

  O que você praticou:

  ✓  Build de imagem Docker e carregamento no Kind
  ✓  Repositório Git auto-hospedado (Gitea)
  ✓  ArgoCD monitorando e sincronizando o cluster
  ✓  Integração com AWS emulada (Floci/S3)
  ✓  GitOps na prática — mudanças via commit
  ✓  Rollback via git revert

  ══════════════════════════════════════════
  Para remover tudo: ./teardown.sh
  ══════════════════════════════════════════

EOF
}

# ── Menu principal ────────────────────────────────────────────────────────────
main() {
  echo -e "\n🧪  ${CYAN}${BOLD}DevOps Essentials${NC} — Laboratório Guiado\n"

  if [[ "${1:-all}" == "all" ]]; then
    passo_0_build_imagem
    passo_1_push_manifests
    passo_2_argocd_application
    passo_3_observar_sync
    passo_4_testar_app
    passo_5_escalar
    passo_6_rollback
    sumario_final
  else
    # Permite rodar um passo específico: ./lab.sh 3
    case "$1" in
      0) passo_0_build_imagem ;;
      1) passo_1_push_manifests ;;
      2) passo_2_argocd_application ;;
      3) passo_3_observar_sync ;;
      4) passo_4_testar_app ;;
      5) passo_5_escalar ;;
      6) passo_6_rollback ;;
      *) echo "Uso: $0 [0-6|all]"; exit 1 ;;
    esac
  fi
}

main "${1:-all}"
