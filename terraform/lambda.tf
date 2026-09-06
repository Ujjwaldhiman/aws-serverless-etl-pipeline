############################################
# Package the Lambda code
############################################

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/employees_csv_validator.py"
  output_path = "${path.module}/build/employees_csv_validator.zip"
}

############################################
# Lambda function
############################################

resource "aws_lambda_function" "csv_validator" {
  function_name    = "${var.project_name}-csv-validator"
  role             = aws_iam_role.lambda_validator.arn
  handler          = "employees_csv_validator.handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.etl_pipeline.arn
    }
  }
}

############################################
# Allow S3 to invoke the Lambda
############################################

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.csv_validator.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.data_lake.arn
}

############################################
# S3 -> Lambda trigger on raw/*.csv uploads
############################################

resource "aws_s3_bucket_notification" "raw_csv_trigger" {
  bucket = aws_s3_bucket.data_lake.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.csv_validator.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
