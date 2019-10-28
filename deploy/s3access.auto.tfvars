
monitoring_bucket = ""
aws_region = ""

access_trail_bucket = ""
access_trail_prefix = ""

cloudwatch_log_retention_in_days = 14
lambda_timeout = 60

transition_rule = "{\"STANDARD_IA\":30}"
scheduler_expression = "rate(30 minutes)"