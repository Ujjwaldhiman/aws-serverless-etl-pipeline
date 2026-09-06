############################################
# Upload the Glue script to S3
############################################

resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "scripts/employees_etl_job.py"
  source = "${path.module}/../glue/employees_etl_job.py"
  etag   = filemd5("${path.module}/../glue/employees_etl_job.py")
}

############################################
# Glue ETL job
############################################

resource "aws_glue_job" "etl_job" {
  name              = "${var.project_name}-etl-job"
  role_arn          = aws_iam_role.glue_etl.arn
  glue_version      = "4.0"
  number_of_workers = 2
  worker_type       = "G.1X"
  timeout           = 10 # minutes - this is a small demo job

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.data_lake.id}/${aws_s3_object.glue_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--SOURCE_PATH"                     = "s3://${aws_s3_bucket.data_lake.id}/raw/employees.csv"
    "--TARGET_PATH"                     = "s3://${aws_s3_bucket.data_lake.id}/processed/employees/"
    "--job-language"                    = "python"
    "--enable-continuous-cloudwatch-log" = "true"
  }
}
