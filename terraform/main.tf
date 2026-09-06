############################################
# S3 Data Lake
############################################

resource "aws_s3_bucket" "data_lake" {
  bucket = var.data_lake_bucket_name

  tags = {
    Project = var.project_name
  }
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Zone "folders" - S3 has no real folders, these are zero-byte objects
# used purely to establish the raw / processed / curated / athena-results prefixes
resource "aws_s3_object" "zones" {
  for_each = toset(["raw/", "processed/", "curated/", "athena-results/"])

  bucket  = aws_s3_bucket.data_lake.id
  key     = each.value
  content = ""
}

############################################
# Glue Data Catalog
############################################

resource "aws_glue_catalog_database" "data_lake" {
  name = replace("${var.project_name}_catalog", "-", "_")
}

resource "aws_glue_crawler" "employees" {
  name          = "${var.project_name}-employees-parquet-crawler"
  database_name = aws_glue_catalog_database.data_lake.name
  role          = aws_iam_role.glue_etl.arn

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.id}/processed/employees/"
  }
}

############################################
# SNS topic for pipeline error alerts
############################################

resource "aws_sns_topic" "lambda_errors" {
  name = "${var.project_name}-lambda-errors-alert"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.lambda_errors.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

############################################
# IAM: Lambda execution role
############################################

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_validator" {
  name               = "${var.project_name}-csv-validator-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_validator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_s3_access" {
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.data_lake.arn, "${aws_s3_bucket.data_lake.arn}/*"]
  }
  statement {
    actions   = ["states:StartExecution"]
    resources = ["*"] # scope down to the specific state machine ARN in production
  }
}

resource "aws_iam_role_policy" "lambda_s3_access" {
  name   = "${var.project_name}-lambda-s3-access"
  role   = aws_iam_role.lambda_validator.id
  policy = data.aws_iam_policy_document.lambda_s3_access.json
}

############################################
# IAM: Glue ETL role
############################################

data "aws_iam_policy_document" "glue_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_etl" {
  name               = "${var.project_name}-glue-etl-role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume.json
}

resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_etl.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

data "aws_iam_policy_document" "glue_s3_access" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.data_lake.arn, "${aws_s3_bucket.data_lake.arn}/*"]
  }
}

resource "aws_iam_role_policy" "glue_s3_access" {
  name   = "${var.project_name}-glue-s3-access"
  role   = aws_iam_role.glue_etl.id
  policy = data.aws_iam_policy_document.glue_s3_access.json
}

############################################
# IAM: Step Functions role
############################################

data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "step_functions" {
  name               = "${var.project_name}-step-functions-etl-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
}

data "aws_iam_policy_document" "sfn_glue_access" {
  statement {
    actions   = ["glue:StartJobRun", "glue:GetJobRun", "glue:GetJobRuns", "glue:BatchStopJobRun"]
    resources = ["*"] # scope down to the specific Glue job ARN in production
  }
}

resource "aws_iam_role_policy" "sfn_glue_access" {
  name   = "${var.project_name}-sfn-glue-access"
  role   = aws_iam_role.step_functions.id
  policy = data.aws_iam_policy_document.sfn_glue_access.json
}
