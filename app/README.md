# DevOpsLab-HelloWorld

Aplicação Flask usada no laboratório GitOps do curso DevOps Essentials.

## Rodar localmente

**Pré-requisitos:** Python 3.10+

```bash
# Instalar dependências
pip install -r requirements.txt

# Subir a aplicação
python app.py
```

Acesse em: http://localhost:5000

### Com virtualenv

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

## Rodar com Docker

```bash
docker build -t devopslab-helloworld .
docker run -p 5000:5000 devopslab-helloworld
```

Acesse em: http://localhost:5000

## Endpoints

| Rota | Descrição |
|---|---|
| `GET /` | Página principal com trilhas de cursos |
| `GET /health` | Health check (usado pelos probes do Kubernetes) |

```bash
curl http://localhost:5000/health
# {"status": "ok", "version": "1.0.0"}
```

## No laboratório GitOps

No lab do curso, a aplicação roda dentro de um cluster **Kind** e é gerenciada pelo **ArgoCD**. Qualquer alteração feita aqui (ex: mudar o texto do alert bar) deve ser commitada e enviada ao **Gitea** — o ArgoCD detecta a mudança e faz o redeploy automaticamente.

```bash
# Exemplo: após editar templates/index.html
git add .
git commit -m "feat: atualiza mensagem do alert bar"
git push
# ArgoCD sincroniza em até 3 minutos
```
