aws_region = ""
monitoring_bucket = ""
access_trail_bucket = ""
access_trail_prefix = ""
cloudwatch_log_retention_in_days = 14
lambda_timeout = 60
transition_rule = "{\"STANDARD_IA\":30}"
scheduler_expression = "rate(30 minutes)"

# Terraform backend configuration
terraform_backend_bucket = ""
terraform_backend_key = ""
terraform_backend_region = "us-east-1"