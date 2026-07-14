"""
Testa os recursos AWS criados pelo Terraform no Floci.
Execute após o terraform apply:
  python3 test_aws.py
"""
import boto3
import sys

ENDPOINT = "http://localhost:4566"
BUCKET   = "devops-essentials-lab"
QUEUE    = "devops-essentials-lab-queue"

def client(service):
    return boto3.client(
        service,
        endpoint_url=ENDPOINT,
        aws_access_key_id="test",
        aws_secret_access_key="test",
        region_name="us-east-1",
    )

def test_s3():
    s3 = client("s3")

    # Lista buckets
    buckets = [b["Name"] for b in s3.list_buckets().get("Buckets", [])]
    assert BUCKET in buckets, f"Bucket '{BUCKET}' não encontrado"
    print(f"  ✓  S3 — bucket '{BUCKET}' existe")

    # Lê o arquivo criado pelo Terraform
    obj = s3.get_object(Bucket=BUCKET, Key="hello-devops.txt")
    content = obj["Body"].read().decode()
    assert "DevOps Essentials" in content
    print(f"  ✓  S3 — objeto 'hello-devops.txt' lido: {content!r}")

    # Upload de novo arquivo
    s3.put_object(Bucket=BUCKET, Key="teste.txt", Body=b"teste via Python")
    print("  ✓  S3 — upload de 'teste.txt' bem-sucedido")

def test_sqs():
    sqs = client("sqs")

    # Envia mensagem
    queue_url = f"{ENDPOINT}/000000000000/{QUEUE}"
    sqs.send_message(QueueUrl=queue_url, MessageBody="Mensagem de teste DevOps")
    print("  ✓  SQS — mensagem enviada")

    # Recebe mensagem
    resp = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=1)
    msgs = resp.get("Messages", [])
    assert len(msgs) > 0, "Nenhuma mensagem recebida"
    print(f"  ✓  SQS — mensagem recebida: {msgs[0]['Body']!r}")

def main():
    print("\n🧪  Testando recursos AWS no Floci...\n")
    errors = []

    for test in [test_s3, test_sqs]:
        try:
            test()
        except Exception as e:
            errors.append(f"  ✗  {test.__name__}: {e}")

    if errors:
        print("\nFalhas:")
        for e in errors:
            print(e)
        sys.exit(1)
    else:
        print("\n  ✓  Todos os testes passaram!\n")

if __name__ == "__main__":
    main()
