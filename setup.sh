#!/usr/bin/env bash
# DevOps Essentials — Setup do laboratório local
# Roda uma vez antes da aula. Cria o cluster Kind, instala Gitea, ArgoCD e Floci.
set -euo pipefail

# ── Cores e helpers ──────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log()   { echo -e "${GREEN}✓${NC}  $1"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $1"; }
err()   { echo -e "${RED}✗${NC}  $1"; exit 1; }
info()  { echo -e "${BLUE}⏳${NC}  $1"; }
sep()   { echo -e "\n${BLUE}──────────────────────────────────────────${NC}\n"; }

# ── Variáveis do lab ─────────────────────────────────────────────────────────
CLUSTER_NAME="devops-lab"
GITEA_NS="gitea"
ARGOCD_NS="argocd"
TOOLS_NS="tools"
GITEA_ADMIN="gitadmin"
GITEA_PASS="gitadmin123"
GITEA_EMAIL="admin@devops.local"
GITEA_REPO="devops-lab"
ARGOCD_VERSION="v2.12.0"
GITEA_CHART_VERSION="10.*"

# ── 1. Pré-requisitos ────────────────────────────────────────────────────────
check_prereqs() {
  sep
  info "Verificando pré-requisitos..."

  local missing=()
  for cmd in docker kubectl helm kind; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Ferramentas não encontradas: ${missing[*]}
    Instale antes de continuar:
      kind:    https://kind.sigs.k8s.io/docs/user/quick-start/#installation
      helm:    https://helm.sh/docs/intro/install/
      kubectl: https://kubernetes.io/docs/tasks/tools/"
  fi

  docker info &>/dev/null || err "Docker não está rodando. Inicie o Docker e tente novamente."

  # Verifica RAM disponível
  local ram_gb
  if [[ "$(uname)" == "Darwin" ]]; then
    ram_gb=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
  else
    ram_gb=$(awk '/MemTotal/ { printf "%d", $2/1024/1024 }' /proc/meminfo)
  fi
  [[ "$ram_gb" -lt 6 ]] && warn "RAM detectada: ${ram_gb}GB. O lab pode ser lento com menos de 8GB."

  log "Pré-requisitos OK — Docker, kubectl, helm, kind encontrados (RAM: ${ram_gb}GB)"
}

# ── 2. Cluster Kind ──────────────────────────────────────────────────────────
create_cluster() {
  sep
  info "Criando cluster Kind '${CLUSTER_NAME}'..."

  if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
    warn "Cluster '${CLUSTER_NAME}' já existe. Pulando criação."
    kubectl cluster-info --context "kind-${CLUSTER_NAME}" &>/dev/null
    return
  fi

  # extraPortMappings mapeiam portas do container Kind para o host,
  # permitindo acesso aos serviços via localhost sem port-forward manual.
  cat > /tmp/kind-devops-lab.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30000   # Gitea HTTP
        hostPort: 3000
        protocol: TCP
      - containerPort: 30080   # ArgoCD UI
        hostPort: 8080
        protocol: TCP
      - containerPort: 30090   # Aplicação Flask
        hostPort: 9090
        protocol: TCP
      - containerPort: 30066   # Floci (AWS emulator)
        hostPort: 4566
        protocol: TCP
  - role: worker
EOF

  kind create cluster --config /tmp/kind-devops-lab.yaml
  kubectl cluster-info --context "kind-${CLUSTER_NAME}"
  log "Cluster Kind '${CLUSTER_NAME}' criado (1 control-plane + 1 worker)"
}

# ── 3. Gitea ─────────────────────────────────────────────────────────────────
install_gitea() {
  sep
  info "Instalando Gitea via Helm..."

  helm repo add gitea-charts https://dl.gitea.com/charts/ --force-update &>/dev/null
  helm repo update &>/dev/null

  kubectl create namespace "$GITEA_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  # SQLite evita a necessidade de puxar imagem do PostgreSQL no Kind,
  # tornando o setup mais rápido e sem dependência de registry externo.
  helm upgrade --install gitea gitea-charts/gitea \
    --namespace "$GITEA_NS" \
    --version "$GITEA_CHART_VERSION" \
    --set gitea.admin.username="$GITEA_ADMIN" \
    --set gitea.admin.password="$GITEA_PASS" \
    --set gitea.admin.email="$GITEA_EMAIL" \
    --set gitea.config.mailer.ENABLED=false \
    --set gitea.config.service.DISABLE_REGISTRATION=false \
    --set gitea.config.server.DOMAIN=localhost \
    --set gitea.config.server.ROOT_URL="http://localhost:3000" \
    --set gitea.config.database.DB_TYPE=sqlite3 \
    --set service.http.type=NodePort \
    --set "service.http.nodePort=30000" \
    --set persistence.enabled=false \
    --set "redis-cluster.enabled=false" \
    --set "postgresql-ha.enabled=false" \
    --set "postgresql.enabled=false" \
    --wait --timeout=8m

  log "Gitea instalado"
  _configure_gitea
}

_configure_gitea() {
  info "Aguardando Gitea responder na porta 3000..."
  local attempts=0
  until curl -sf http://localhost:3000 -o /dev/null; do
    [[ $attempts -ge 36 ]] && err "Gitea não respondeu após 3 minutos"
    sleep 5
    (( attempts++ ))
  done

  info "Criando repositório '${GITEA_REPO}'..."
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST http://localhost:3000/api/v1/user/repos \
    -H "Content-Type: application/json" \
    -u "${GITEA_ADMIN}:${GITEA_PASS}" \
    -d "{\"name\":\"${GITEA_REPO}\",\"private\":false,\"auto_init\":true,\"default_branch\":\"main\"}")

  if [[ "$http_code" == "201" ]]; then
    log "Repositório '${GITEA_REPO}' criado em http://localhost:3000/${GITEA_ADMIN}/${GITEA_REPO}"
  elif [[ "$http_code" == "409" ]]; then
    warn "Repositório '${GITEA_REPO}' já existe"
  else
    warn "Criação do repositório retornou HTTP ${http_code} — verifique manualmente"
  fi
}

# ── 4. ArgoCD ────────────────────────────────────────────────────────────────
install_argocd() {
  sep
  info "Instalando ArgoCD ${ARGOCD_VERSION}..."

  kubectl create namespace "$ARGOCD_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  kubectl apply -n "$ARGOCD_NS" \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

  info "Aguardando ArgoCD server ficar pronto..."
  kubectl rollout status deployment/argocd-server -n "$ARGOCD_NS" --timeout=6m

  # Expõe a UI via NodePort mapeado para localhost:8080
  kubectl patch svc argocd-server -n "$ARGOCD_NS" -p '{
    "spec": {
      "type": "NodePort",
      "ports": [
        {"name":"http","port":80,"targetPort":8080,"nodePort":30080,"protocol":"TCP"}
      ]
    }
  }'

  log "ArgoCD instalado"
}

# ── 5. Floci (emulador AWS) ───────────────────────────────────────────────────
install_floci() {
  sep
  info "Instalando Floci (emulador AWS local) no cluster..."

  # Rodamos o Floci dentro do cluster Kubernetes em vez de no Docker host.
  # Isso evita problemas de networking entre o Kind e o host em Linux/macOS
  # e mantém toda a stack no mesmo contexto Kubernetes.
  kubectl create namespace "$TOOLS_NS" --dry-run=client -o yaml | kubectl apply -f - &>/dev/null

  kubectl apply -n "$TOOLS_NS" -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: floci
  labels:
    app: floci
spec:
  replicas: 1
  selector:
    matchLabels:
      app: floci
  template:
    metadata:
      labels:
        app: floci
    spec:
      containers:
        - name: floci
          image: localstack/localstack:3
          ports:
            - containerPort: 4566
          env:
            - name: SERVICES
              value: "s3,sqs,lambda,dynamodb"
            - name: DEFAULT_REGION
              value: "us-east-1"
            - name: DEBUG
              value: "0"
          readinessProbe:
            httpGet:
              path: /_localstack/health
              port: 4566
            initialDelaySeconds: 10
            periodSeconds: 5
            failureThreshold: 12
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: floci
  labels:
    app: floci
spec:
  selector:
    app: floci
  type: NodePort
  ports:
    - port: 4566
      targetPort: 4566
      nodePort: 30066
EOF

  info "Aguardando Floci ficar pronto..."
  kubectl rollout status deployment/floci -n "$TOOLS_NS" --timeout=4m
  log "Floci iniciado — acessível em localhost:4566 e floci.tools.svc.cluster.local:4566"
}

# ── 6. Health checks ─────────────────────────────────────────────────────────
health_check() {
  sep
  info "Verificando saúde dos serviços..."

  # Gitea
  curl -sf http://localhost:3000 -o /dev/null \
    && log "Gitea     → http://localhost:3000  ✓" \
    || warn "Gitea     → não respondeu (verifique: kubectl get pods -n gitea)"

  # ArgoCD
  curl -sf http://localhost:8080 -o /dev/null \
    && log "ArgoCD    → http://localhost:8080  ✓" \
    || warn "ArgoCD    → não respondeu (verifique: kubectl get pods -n argocd)"

  # Floci — testa via NodePort exposto no host
  curl -sf http://localhost:4566/_localstack/health -o /dev/null \
    && log "Floci     → http://localhost:4566  ✓" \
    || warn "Floci     → não respondeu ainda (pode demorar mais alguns segundos)"
}

# ── 7. Sumário final ─────────────────────────────────────────────────────────
print_summary() {
  local argocd_pass
  argocd_pass=$(kubectl -n "$ARGOCD_NS" get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d) \
    || argocd_pass="(rode: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"

  sep
  cat <<SUMMARY

  🚀  DevOps Lab pronto!
  ════════════════════════════════════════════

  Gitea  (servidor Git)
  ├─ URL:   http://localhost:3000
  ├─ Usuário: ${GITEA_ADMIN}
  └─ Senha:   ${GITEA_PASS}

  Repositório do lab:
  └─ http://localhost:3000/${GITEA_ADMIN}/${GITEA_REPO}

  ArgoCD  (GitOps)
  ├─ URL:   http://localhost:8080
  ├─ Usuário: admin
  └─ Senha:   ${argocd_pass}

  Floci  (emulador AWS — S3, SQS, Lambda, DynamoDB)
  └─ http://localhost:4566

  Aplicação Flask  (após o lab)
  └─ http://localhost:9090

  ════════════════════════════════════════════
  Próximo passo: ./lab.sh
  ════════════════════════════════════════════

SUMMARY
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  echo -e "\n🛠  ${GREEN}DevOps Essentials${NC} — Setup do Laboratório\n"
  check_prereqs
  create_cluster
  install_gitea
  install_argocd
  install_floci
  health_check
  print_summary
}

main "$@"
