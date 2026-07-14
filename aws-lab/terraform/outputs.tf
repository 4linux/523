output "sqs_url" {
  description = "URL da fila SQS criada"
  value       = aws_sqs_queue.lab.url
}

output "floci_endpoint" {
  description = "Endpoint do Floci utilizado"
  value       = "http://localhost:4566"
}
