resource "local_file" "test" {
  content  = <<-EOT
    #!/bin/bash
    aws lambda invoke --function-name ${aws_lambda_function.orchestrator.function_name} --region ${var.aws_region} --cli-binary-format raw-in-base64-out response.json
    cat response.json && rm response.json
    echo ""
  EOT
  filename = "${path.module}/test/run.sh"
}
