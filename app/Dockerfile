# Stage 1 — instala dependências isoladas para não poluir a imagem final
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --target=/build/deps -r requirements.txt


# Stage 2 — imagem final mínima, apenas o necessário para rodar
FROM python:3.12-slim

WORKDIR /app

COPY --from=builder /build/deps /app/deps
ENV PYTHONPATH=/app/deps

# Copia o código e os assets estáticos
COPY app.py .
COPY templates/ templates/
COPY static/ static/

EXPOSE 5000

RUN useradd -m appuser
USER appuser

# Gunicorn é mais estável que o servidor de desenvolvimento do Flask em produção
CMD ["python", "-m", "gunicorn", "-b", "0.0.0.0:5000", "--timeout", "60", "app:app"]
