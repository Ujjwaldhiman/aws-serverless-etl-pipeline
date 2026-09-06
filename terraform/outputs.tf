output "data_lake_bucket" {
  value = aws_s3_bucket.data_lake.id
}

output "glue_database_name" {
  value = aws_glue_catalog_database.data_lake.name
}

output "lambda_role_arn" {
  value = aws_iam_role.lambda_validator.arn
}

output "glue_role_arn" {
  value = aws_iam_role.glue_etl.arn
}

output "step_functions_role_arn" {
  value = aws_iam_role.step_functions.arn
}

output "sns_topic_arn" {
  value = aws_sns_topic.lambda_errors.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.csv_validator.function_name
}

output "glue_job_name" {
  value = aws_glue_job.etl_job.name
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.etl_pipeline.arn
}

output "athena_results_location" {
  value = "s3://${aws_s3_bucket.data_lake.id}/athena-results/"
}
