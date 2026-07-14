# DevOps Essentials Lab — 523

Lab GitOps 100% local do curso **DevOps Essentials (523)** da 4Linux.

Você vai construir um ambiente completo de GitOps — repositório Git, operador de deploy automático, aplicação web e emulador AWS — tudo rodando na sua máquina, sem conta em cloud, sem cartão de crédito.

---

## O que você vai aprender

- Subir um cluster Kubernetes local com **Kind**
- Hospedar um repositório Git com **Gitea** (self-hosted)
- Fazer deploys automáticos via **ArgoCD** (GitOps)
- Escalar e fazer rollback de aplicações usando apenas `git push`
- Emular serviços AWS localmente com **Floci**
- Provisionar infraestrutura como código com **OpenTofu**

---

## Arquitetura

```
┌─────────────────────────────────────────────────────────┐
│                     Sua máquina                         │
│                                                         │
│  Browser / Terminal                                     │
│  localhost:3000  →  Gitea  (Git server)                 │
│  localhost:8080  →  ArgoCD (GitOps operator)            │
│  localhost:9090  →  Aplicação Flask                     │
│  localhost:4566  →  Floci  (AWS local)                  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │              Cluster Kind (Docker)               │   │
│  │                                                  │   │
│  │  namespace: gitea                                │   │
│  │  └─ gitea-http (Git server via Helm)             │   │
│  │                                                  │   │
│  │  namespace: argocd                               │   │
│  │  └─ argocd-server                                │   │
│  │     └─ observa gitea/devops-lab.git              │   │
│  │        └─ aplica k8s/ no cluster                 │   │
│  │                                                  │   │
│  │  namespace: devops-lab                           │   │
│  │  └─ devops-app (Flask — DevOpsLab HelloWorld)    │   │
│  │                                                  │   │
│  │  namespace: tools                                │   │
│  │  └─ floci (S3, SQS, DynamoDB, Lambda...)         │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### Fluxo GitOps

```
git push → Gitea → ArgoCD detecta (~3 min) → kubectl apply → app atualizada
```

Rollback = `git revert` — o cluster nunca é modificado diretamente.

---

## Pré-requisitos

| Ferramenta | Versão mínima | Instalação |
|---|---|---|
| Docker | 24+ | [docs.docker.com](https://docs.docker.com/engine/install/) |
| kind | 0.27+ | [kind.sigs.k8s.io](https://kind.sigs.k8s.io) |
| kubectl | 1.32+ | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| helm | 3.16+ | [helm.sh](https://helm.sh/docs/intro/install/) |

**Hardware recomendado:** 8 GB RAM, 4 CPUs, 20 GB de disco livre.

---

## Início rápido

```bash
# 1. Clonar o repositório
git clone https://github.com/4linux/523-devops-essentials-lab.git
cd 523-devops-essentials-lab

# 2. Subir o lab completo (~5-10 minutos na primeira vez)
bash setup.sh
```

Após o setup:

| Serviço | Endereço | Credenciais |
|---|---|---|
| **Gitea** | http://localhost:3000 | `gitadmin` / `gitadmin123` |
| **ArgoCD** | http://localhost:8080 | `admin` / (ver abaixo) |
| **Aplicação** | http://localhost:9090 | — |
| **Floci** | http://localhost:4566 | `test` / `test` |

Senha inicial do ArgoCD:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

---

## Estrutura do repositório

```
523-devops-essentials-lab/
│
├── setup.sh          # Sobe cluster Kind + instala Gitea, ArgoCD, Floci
├── teardown.sh       # Destrói o cluster completamente
├── lab.sh            # Helpers para o lab guiado
│
├── app/              # Aplicação Flask (DevOpsLab HelloWorld)
│   ├── app.py        # Rotas: / e /health
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── static/       # CSS e imagens
│   └── templates/    # HTML (index.html)
│
├── k8s/              # Manifests Kubernetes (gerenciados pelo ArgoCD)
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── kustomization.yaml
│
├── argocd/
│   └── application.yaml   # ArgoCD Application apontando para o Gitea
│
└── aws-lab/               # Lab AWS local com Floci
    ├── test_aws.py        # Testes com boto3
    └── terraform/
        ├── main.tf        # Provider AWS → Floci (SQS via OpenTofu)
        ├── variables.tf
        └── outputs.tf
```

---

## Exercícios do lab

### Exercício 1 — Ciclo GitOps completo

Altere a mensagem de boas-vindas da aplicação e veja o ArgoCD fazer o deploy automaticamente.

```bash
# 1. Editar o alert bar em app/templates/index.html
#    Linha: <div class="alert">DevOps Essentials Lab — ...</div>

# 2. Build da nova imagem
docker build -t devops-app:v2 app/
kind load docker-image devops-app:v2 --name devops-lab

# 3. Atualizar a imagem no deployment
sed -i 's|devops-app:.*|devops-app:v2|' k8s/deployment.yaml

# 4. Commitar e enviar ao Gitea
git add .
git commit -m "feat: atualiza mensagem do alert bar"
git push

# 5. Aguardar o ArgoCD sincronizar (~3 minutos)
# Acompanhe em: http://localhost:8080
# Resultado em: http://localhost:9090
```

### Exercício 2 — Escalar a aplicação

```bash
sed -i 's/replicas: 1/replicas: 3/' k8s/deployment.yaml

git add k8s/deployment.yaml
git commit -m "scale: aumenta réplicas para 3"
git push

# Verificar os pods subindo
kubectl get pods -n devops-lab -w
```

### Exercício 3 — Rollback via Git

```bash
git revert HEAD --no-edit
git push

# O ArgoCD reverte o cluster automaticamente
# Sem kubectl, sem acesso direto ao cluster
```

### Exercício 4 — selfHeal: o Git sempre vence

```bash
# Tente modificar o cluster diretamente (fora do Git)
kubectl scale deployment devops-app -n devops-lab --replicas=5

# Aguarde ~3 minutos — o ArgoCD vai reverter para o que está no Git
kubectl get pods -n devops-lab
```

### Exercício 5 — SQS com OpenTofu

```bash
cd aws-lab/terraform

tofu init
tofu plan
tofu apply -auto-approve

# Verificar a fila criada
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

aws sqs list-queues

# Enviar e receber mensagem
aws sqs send-message \
  --queue-url http://localhost:4566/000000000000/devops-essentials-lab-queue \
  --message-body "Olá do DevOps Essentials!"

aws sqs receive-message \
  --queue-url http://localhost:4566/000000000000/devops-essentials-lab-queue

# Destruir a fila
tofu destroy -auto-approve
```

### Exercício 6 — S3 com AWS CLI

```bash
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

# Criar bucket e fazer upload
aws s3 mb s3://devops-essentials-lab
echo "Olá do DevOps Essentials!" | aws s3 cp - s3://devops-essentials-lab/hello.txt

# Listar e ler
aws s3 ls s3://devops-essentials-lab/
aws s3 cp s3://devops-essentials-lab/hello.txt -

# Limpar
aws s3 rb s3://devops-essentials-lab --force
```

---

## Ferramentas do lab

| Ferramenta | Papel no lab |
|---|---|
| **Kind** | Cria um cluster Kubernetes dentro do Docker — sem precisar de VM |
| **Gitea** | Servidor Git self-hosted — o "GitHub" local do lab |
| **ArgoCD** | Operador GitOps — observa o Gitea e sincroniza o cluster automaticamente |
| **Floci** | Emulador local de serviços AWS (S3, SQS, DynamoDB, Lambda) |
| **OpenTofu** | IaC open source — fork do Terraform pela Linux Foundation (Apache 2.0) |
| **Flask** | Framework web Python — base da aplicação de demonstração |
| **Helm** | Gerenciador de pacotes Kubernetes — instala Gitea e ArgoCD |

---

## Troubleshooting

### Pod em Pending ou ImagePullBackOff

```bash
kubectl describe pod -n devops-lab <nome-do-pod>

# Imagem não carregada no Kind
kind load docker-image devops-app:latest --name devops-lab
```

### ArgoCD não conecta no Gitea

```bash
kubectl exec -n argocd deploy/argocd-server -- \
  curl -sf http://gitea-http.gitea.svc.cluster.local:3000

kubectl get pods -n gitea
```

### Floci não responde

```bash
kubectl get pods -n tools
kubectl logs -n tools deploy/floci
curl http://localhost:4566/_localstack/health
```

### Porta já em uso no host

```bash
lsof -i :3000
lsof -i :8080
# Pare o processo ou rode: bash teardown.sh
```

### ArgoCD não sincroniza automaticamente

```bash
# Force sync manual
kubectl -n argocd patch app devops-app \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

---

## Destruir o lab

```bash
bash teardown.sh
```

Remove o cluster Kind e todos os recursos. Não deixa nada para trás.

---

## Sobre o curso

Este lab faz parte do curso **DevOps Essentials (523)** da [4Linux](https://4linux.com.br).

Próximos passos na trilha:

- [CloudOps: DevOps, SRE, GitOps e AIOps](https://4linux.com.br/cursos/produto/cloudops-plataformas-modernas-com-devops-sre-gitops-e/)
- [CI/CD com Jenkins, Nexus, SonarQube e GitLab-CI](https://4linux.com.br/cursos/produto/ci-cd-integracao-e-entrega-continua-com-jenkins-nexus/)
- [Kubernetes: Orquestração de Ambientes Escaláveis CKAD/CKA](https://4linux.com.br/cursos/produto/kubernetes-orquestracao-de-ambientes-escalaveis/)
- [IA no Universo Kubernetes](https://4linux.com.br/cursos/produto/ia-no-universo-kubernetes/)
