# terraform init
# export AWS_ACCESS_KEY_ID=
# export AWS_SECRET_ACCESS_KEY=
# export AWS_REGION=
# export TF_VAR_name=
# export TF_VAR_github_app_key_base64=
# export TF_VAR_github_app_id=
# export TF_VAR_github_webhook_secret=
# export TF_VAR_email=
# export TF_VAR_repository_white_list=
# export TF_VAR_runner_white_list=
# terraform apply

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.84.0"
    }
    local = {
      source = "hashicorp/local"
    }
    random = {
      source = "hashicorp/random"
    }
  }

  required_version = "~> 1.3.7"
}

locals {
  tags = {
    Name = "Custom GitHub Runners"
    Url  = "https://github.com/ipdxco/custom-github-runners"
  }
  filters = [
    {
      name = "Connection Refused"
      metric = "ConnectionRefused"
      pattern = "Connection refused"
      group = "runner-startup"
    },
    {
      name = "Parameter Not Found"
      metric = "ParameterNotFound"
      pattern = "ParameterNotFound"
      group = "runner-startup"
    },
    {
      name = "HTTP Request Timed Out"
      metric = "HttpRequestTimedOut"
      pattern = "HTTP request timed out"
      group = "runner-startup"
    }
  ]
}

provider "aws" {}

variable "name" {}

variable "github_app_key_base64" {}

variable "github_app_id" {}

variable "github_webhook_secret" {}

variable "email" {}

variable "repository_white_list" {
  type = list(string)
}

variable "runner_white_list" {
  type = list(string)
}

data "aws_region" "default" {}

data "aws_s3_bucket" "custom-github-runners" {
  bucket = var.name
}

data "aws_caller_identity" "current" {}

# RETENTION

resource "aws_s3_bucket_lifecycle_configuration" "custom-github-runners_v2" {
  count = length(local.runners) > 0 ? 1 : 0

  bucket = data.aws_s3_bucket.custom-github-runners.id

  # artifacts.tf
  dynamic "rule" {
    for_each = local.runners

    content {
      id = rule.key
      filter {
        prefix = "${rule.key}/"
      }
      expiration {
        days = 90
      }
      status = "Enabled"
    }
  }
}

# LOG TO METRICS

resource "aws_cloudwatch_log_metric_filter" "custom-github-runners" {
  for_each = { for config in flatten([
    for runner in keys(module.multi-runner.runners_map) : [
      for filter in local.filters : merge(filter, { runner = runner })
    ]
  ]) : "/github-self-hosted-runners/multi-${config.runner}/${config.group}/${config.metric}" => config }

  name           = each.value.name
  pattern        = each.value.pattern
  log_group_name = "/github-self-hosted-runners/multi-${each.value.runner}/${each.value.group}"

  metric_transformation {
    name          = each.value.metric
    namespace     = "/github-self-hosted-runners/multi-${each.value.runner}/${each.value.group}"
    value         = "1"
    default_value = null
    unit          = "Count"
  }
}

resource "aws_sns_topic" "custom-github-runners" {
  name = "custom-github-runners"
}

resource "aws_sns_topic_subscription" "custom-github-runners" {
  count = var.email != "" ? 1 : 0

  topic_arn = aws_sns_topic.custom-github-runners.arn
  protocol  = "email"
  endpoint  = var.email
}

resource "aws_cloudwatch_metric_alarm" "custom-github-runners" {
  for_each = aws_cloudwatch_log_metric_filter.custom-github-runners

  alarm_name        = "${each.value.metric_transformation[0].namespace}/${each.value.metric_transformation[0].name}"
  alarm_description = "${each.value.name} exceeded threshold"
  actions_enabled   = true

  alarm_actions             = [aws_sns_topic.custom-github-runners.arn]
  ok_actions                = []
  insufficient_data_actions = []

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  threshold           = "0"
  unit                = "Count"

  datapoints_to_alarm                   = "1"
  treat_missing_data                    = "notBreaching"

  # conflicts with metric_query
  metric_name        = each.value.metric_transformation[0].name
  namespace          = each.value.metric_transformation[0].namespace
  period             = "600"
  statistic          = "Sum"

  tags = local.tags
}
