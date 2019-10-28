variable "backend_bucket" {
  type = string
}

variable "backend_region" {
  type = string
}

variable "backend_prefix" {
  type = string
}
terraform {
  backend "s3" {}
}

data "terraform_remote_state" "state" {
  backend = "s3"
  config {
    bucket     = "${var.backend_bucket}"
    region     = "${var.backend_region}"
    key        = "${var.backend_prefix}"
  }
}

variable "monitoring_bucket" {
  type = string
}

variable "access_trail_bucket" {
  type = string
}

variable "access_trail_prefix" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cloudwatch_log_retention_in_days" {
  type = string
}

variable "lambda_timeout" {
  type = string
}

variable "transition_rule" {
  type = string
}

variable "scheduler_expression" {
  type    = string
  default = "rate(30 minutes)"
}

variable "lambda_name_s3transitioner" {
  type    = string
  default = "s3transitioner"
}

variable "lambda_name_s3accessmonitor" {
  type    = string
  default = "s3accessmonitor"
}

variable "lambda_name_s3transitionexecutor" {
  type    = string
  default = "s3transitionexecutor"
}

variable "s3transitionpkgname" {
  type    = string
  default = "../S3Transitioner/s3transitioner.zip"
}

variable "s3accessmonitorpkgname" {
  type    = string
  default = "../S3AccessMonitor/s3accessmonitor.zip"
}

variable "s3transitionexecpkgname" {
  type    = string
  default = "../S3TransitionExecutor/s3transitionexecutor.zip"
}

variable "s3accessstoredomain" {
  type    = string
  default = "s3accessstore"
}

data "aws_s3_bucket" "monitoring_bucket" {
  bucket = var.monitoring_bucket
}

provider "aws" {
  region = var.aws_region
}

variable "access_index" {
  type    = string
  default = <<EOF
{
      "settings" : {
        "index" : {
          "number_of_shards" : 3,
          "number_of_replicas" : 1
        }
      }
    }
EOF

}

variable "access_mapping" {
  type    = string
  default = <<EOF
{
   "dynamic_templates":[
      {
         "strings":{
            "mapping":{
               "type":"keyword"
            },
            "match_mapping_type":"string",
            "match":"*"
         }
      }
   ],
   "properties":{
      "access_timestamp":{
         "type":"date"
      },
      "geoip":{
         "properties":{
            "location":{
               "type":"geo_point"
            },
            "ip":{
               "type":"ip"
            }
         }
      }
   }
}
EOF

}

variable "transition_index" {
  type    = string
  default = <<EOF
{
	"settings" : {
        "index" : {
            "number_of_shards" : 3,
            "number_of_replicas" : 1
        }
    }
}
EOF

}

variable "transition_mapping" {
  type    = string
  default = <<EOF
{
    "properties": {
      "access_timestamp":     { "type": "date"  },
      "bucket":  {"type":   "keyword"},
      "object_key": {"type":   "keyword"},
      "storage_class": {"type":   "keyword"},
      "bucket_region": {"type":   "keyword"}
     }
}
EOF

}

resource "aws_iam_role" "s3transitionerrole" {
  name               = "s3transitionerrole"
  assume_role_policy = <<EOF
{"Version": "2012-10-17","Statement": [ { "Action": "sts:AssumeRole","Effect": "Allow","Principal": { "Service": ["lambda.amazonaws.com","edgelambda.amazonaws.com"]}}]}

EOF

}

# Cloud trail creation to monitor S3 bucket for all Read and Write operations
resource "aws_cloudtrail" "s3accesstrail" {
  name                          = "s3accessmonitortrail"
  s3_bucket_name                = var.access_trail_bucket
  s3_key_prefix                 = var.access_trail_prefix
  include_global_service_events = false
  event_selector {
    read_write_type           = "All"
    include_management_events = false
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${data.aws_s3_bucket.monitoring_bucket.arn}/"]
    }
  }
}

resource "aws_lambda_function" "s3transitionexecutor_resource" {
  function_name    = var.lambda_name_s3transitionexecutor
  handler          = "object_transition_handler.lambda_handler"
  role             = aws_iam_role.s3transitionerrole.arn
  runtime          = "ruby2.5"
  filename         = var.s3transitionexecpkgname
  source_code_hash = filebase64sha256(var.s3transitionexecpkgname)
environment {
  variables = {
    ES_HOSTS = "https://${aws_elasticsearch_domain.s3accessstore.endpoint}"
  }
}
depends_on = [
  aws_iam_role_policy_attachment.s3transtionexecutor_logs,
  aws_cloudwatch_log_group.s3transitionexecutor_log_group,
]
timeout = var.lambda_timeout
}

# This is to optionally manage the CloudWatch Log Group for the Lambda Function.
# If skipping this resource configuration, also add "logs:CreateLogGroup" to the IAM policy below.
resource "aws_cloudwatch_log_group" "s3transitionexecutor_log_group" {
name              = "/aws/lambda/${var.lambda_name_s3transitionexecutor}"
retention_in_days = var.cloudwatch_log_retention_in_days
}

# See also the following AWS managed policy: AWSLambdaBasicExecutionRole
resource "aws_iam_policy" "s3transitionexecutor_logging" {
name        = "s3transtionexecutor_logging"
path        = "/"
description = "IAM policy for logging from a lambda - S3transitionexecutor"

policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF

}

resource "aws_iam_role_policy_attachment" "s3transtionexecutor_logs" {
role       = aws_iam_role.s3transitionerrole.name
policy_arn = aws_iam_policy.s3transitionexecutor_logging.arn
}

# Lambda function (s3transitioner) basically check the access store and performs the
# required object transitions.

resource "aws_lambda_function" "s3transitioner_resource" {
function_name    = var.lambda_name_s3transitioner
handler          = "object_transition_handler.lambda_handler"
role             = aws_iam_role.s3transitionerrole.arn
runtime          = "ruby2.5"
filename         = var.s3transitionpkgname
source_code_hash = filebase64sha256(var.s3transitionpkgname)
environment {
variables = {
ES_HOSTS        = "https://${aws_elasticsearch_domain.s3accessstore.endpoint}"
TRANSITION_RULE = var.transition_rule
}
}
depends_on = [
aws_iam_role_policy_attachment.s3transtioner_logs,
aws_cloudwatch_log_group.s3transitioner_log_group,
]
timeout = var.lambda_timeout
}

resource "aws_cloudwatch_event_rule" "s3transitioner_event_rule" {
name                = "S3transitionPeriodicRun"
description         = "Periodic run for S3 Object Transition"
schedule_expression = var.scheduler_expression
}

resource "aws_cloudwatch_event_target" "s3transitioner_event_target" {
arn  = aws_lambda_function.s3transitioner_resource.arn
rule = aws_cloudwatch_event_rule.s3transitioner_event_rule.name
}

resource "aws_lambda_permission" "s3transitioner_permission" {
action        = "lambda:InvokeFunction"
function_name = aws_lambda_function.s3transitioner_resource.function_name
principal     = "events.amazonaws.com"
source_arn    = aws_cloudwatch_event_rule.s3transitioner_event_rule.arn
}

# This is to optionally manage the CloudWatch Log Group for the Lambda Function.
# If skipping this resource configuration, also add "logs:CreateLogGroup" to the IAM policy below.
resource "aws_cloudwatch_log_group" "s3transitioner_log_group" {
name              = "/aws/lambda/${var.lambda_name_s3transitioner}"
retention_in_days = var.cloudwatch_log_retention_in_days
}

# See also the following AWS managed policy: AWSLambdaBasicExecutionRole
resource "aws_iam_policy" "s3transitioner_logging" {
name        = "s3transtioner_logging"
path        = "/"
description = "IAM policy for logging from a lambda - S3transitioner"

policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF

}

resource "aws_iam_role_policy_attachment" "s3transtioner_logs" {
role       = aws_iam_role.s3transitionerrole.name
policy_arn = aws_iam_policy.s3transitioner_logging.arn
}

# Lambda function for S3AcessMonitor

resource "aws_lambda_function" "s3accessmonitor_resource" {
function_name    = var.lambda_name_s3accessmonitor
handler          = "lambda_function.lambda_handler"
role             = aws_iam_role.s3transitionerrole.arn
runtime          = "ruby2.5"
filename         = var.s3accessmonitorpkgname
source_code_hash = filebase64sha256(var.s3accessmonitorpkgname)
environment {
variables = {
ES_HOSTS = "https://${aws_elasticsearch_domain.s3accessstore.endpoint}"
}
}
depends_on = [
aws_iam_role_policy_attachment.s3accessmonitor_logs,
aws_cloudwatch_log_group.s3accessmonitor_log_group,
]
timeout = var.lambda_timeout
}

resource "aws_cloudwatch_event_rule" "s3accessmonitor_event_rule" {
name          = "S3AccessEventRule"
description   = "Monitoring of each and every object Get access"
event_pattern = "{\"detail-type\":[\"AWS API Call via CloudTrail\"],\"source\":[\"aws.s3\"],\"detail\":{\"eventSource\":[\"s3.amazonaws.com\"],\"requestParameters\":{\"bucketName\":[\"s3transition-lambda-poc\"]},\"eventName\":[\"GetObject\",\"PutObject\",\"CompleteMultipartUpload\",\"CopyObject\"]}}"
}

resource "aws_cloudwatch_event_target" "s3accessmonitor_event_target" {
arn  = aws_lambda_function.s3accessmonitor_resource.arn
rule = aws_cloudwatch_event_rule.s3accessmonitor_event_rule.name
}

resource "aws_lambda_permission" "s3accessmonitor_permission" {
action        = "lambda:InvokeFunction"
function_name = aws_lambda_function.s3accessmonitor_resource.function_name
principal     = "events.amazonaws.com"
source_arn    = aws_cloudwatch_event_rule.s3accessmonitor_event_rule.arn
}

resource "aws_cloudwatch_log_group" "s3accessmonitor_log_group" {
name              = "/aws/lambda/${var.lambda_name_s3accessmonitor}"
retention_in_days = var.cloudwatch_log_retention_in_days
}

# See also the following AWS managed policy: AWSLambdaBasicExecutionRole
resource "aws_iam_policy" "s3accessmonitor_logging" {
name        = "s3accessmonitor_logging"
path        = "/"
description = "IAM policy for logging from a lambda - S3AccessMonitor"

policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF

}

resource "aws_iam_role_policy_attachment" "s3accessmonitor_logs" {
role       = aws_iam_role.s3transitionerrole.name
policy_arn = aws_iam_policy.s3accessmonitor_logging.arn
}

# Elastic search creation for access data store
# TODO: commenting it out as it would take more time to create; Comment only when you "DESTROY"

data "aws_region" "current" {
}

data "aws_caller_identity" "current" {
}

resource "aws_elasticsearch_domain" "s3accessstore" {
domain_name = var.s3accessstoredomain
cluster_config {
instance_count         = 2
dedicated_master_count = 1
zone_awareness_enabled = false
instance_type          = "t2.medium.elasticsearch"
}

ebs_options {
ebs_enabled = true
volume_type = "gp2"
volume_size = 10
}
encrypt_at_rest {
enabled = false
}
elasticsearch_version = "7.1"
access_policies       = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "es:*",
      "Principal": "*",
      "Effect": "Allow",
      "Resource": "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.s3accessstoredomain}/*",
      "Condition": {
        "IpAddress": {"aws:SourceIp": ["0.0.0.0/0"]}
      }
    }
  ]
}
POLICY


provisioner "local-exec" {
command = "curl -X PUT https://${aws_elasticsearch_domain.s3accessstore.endpoint}/object_access -H 'content-type: application/json' -d '${var.access_index}'"
}
provisioner "local-exec" {
command = "curl -X PUT https://${aws_elasticsearch_domain.s3accessstore.endpoint}/object_access/_mapping/insert_object_access?include_type_name=true -H 'content-type: application/json' -d '${var.access_mapping}'"
}

provisioner "local-exec" {
command = "curl -X PUT https://${aws_elasticsearch_domain.s3accessstore.endpoint}/object_transition -H 'content-type: application/json' -d '${var.transition_index}'"
}
provisioner "local-exec" {
command = "curl -X PUT https://${aws_elasticsearch_domain.s3accessstore.endpoint}/object_transition/_mapping/insert_object_transition?include_type_name=true -H 'content-type: application/json' -d '${var.transition_mapping}'"
}
}

resource "aws_iam_role_policy_attachment" "s3transitionaccess" {
role       = aws_iam_role.s3transitionerrole.name
policy_arn = aws_iam_policy.s3access.arn
}

resource "aws_iam_role_policy_attachment" "s3transitionlambdaaccess" {
role       = aws_iam_role.s3transitionerrole.name
policy_arn = aws_iam_policy.lambdaaccess.arn
}

resource "aws_iam_policy" "s3access" {
name   = "s3access"
policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": "*"
        }
    ]
}
POLICY

}

resource "aws_iam_policy" "lambdaaccess" {
name   = "lambdaaccess"
policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "lambda:*",
            "Resource": "*"
        }
    ]
}
POLICY

}