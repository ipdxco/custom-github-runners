# terraform init
# export AWS_ACCESS_KEY_ID=
# export AWS_SECRET_ACCESS_KEY=
# export TF_VAR_name=
# terraform apply

terraform {
  required_providers {
    aws = {
      version = "5.84.0"
    }
  }

  required_version = "~> 1.3.7"
}

provider "aws" {
  region = "us-east-1"
}

variable "name" {
  description = "The name to use for S3 bucket, DynamoDB table and IAM users."
  type        = string
}

resource "aws_iam_service_linked_role" "spot" {
  aws_service_name = "spot.amazonaws.com"
}

resource "aws_s3_bucket" "this" {
  bucket = var.name

  tags = {
    Name = "Custom GitHub Runners"
    Url  = "https://github.com/ipdxco/custom-github-runners"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "this" {
    depends_on = [ aws_s3_bucket_ownership_controls.this ]

  bucket = aws_s3_bucket.this.id
  acl    = "private"
}

resource "aws_dynamodb_table" "this" {
  name         = var.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "Custom GitHub Runners"
    Url  = "https://github.com/ipdxco/custom-github-runners"
  }
}

resource "aws_iam_user" "this" {
  name = var.name

  tags = {
    Name = "Custom GitHub Runners"
    Url  = "https://github.com/ipdxco/custom-github-runners"
  }
}

data "aws_iam_policy_document" "this" {
  statement {
    actions = [
      "iam:*",
      "s3:*",
      "ec2:*",
      "events:*",
      "lambda:*",
      "sqs:*",
      "ssm:*",
      "logs:*",
      "apigateway:*",
      "resource-groups:*",
      "kms:*",
      "dynamodb:*",
      "elasticloadbalancing:*"
    ]
    resources = ["*"]
    effect = "Allow"
  }
}

resource "aws_iam_user_policy" "this" {
  name = var.name
  user = "${aws_iam_user.this.name}"

  policy = "${data.aws_iam_policy_document.this.json}"
}

module "github-runner_download-lambda" {
  source  = "github-aws-runners/github-runner/aws//modules/download-lambda"
  version = "6.1.3"
  lambdas = [
    {
      name = "webhook"
      tag  = "v6.1.3"
    },
    {
      name = "runners"
      tag  = "v6.1.3"
    },
    {
      name = "runner-binaries-syncer"
      tag  = "v6.1.3"
    },
    {
      name = "ami-housekeeper"
      tag  = "v6.1.3"
    }
  ]
}
