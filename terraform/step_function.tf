############################################
# Step Functions state machine
#
# NOTE: validation happens once, inside the Lambda, before this
# execution starts (the Lambda passes the validation report in as
# input). That's a small refinement over the original console-built
# version, which re-validated inside the state machine - no reason
# to do the same check twice.
############################################

locals {
  state_machine_definition = jsonencode({
    Comment = "Orchestrates transformation of validated employee CSV uploads"
    StartAt = "CheckValidation"
    States = {
      CheckValidation = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.is_valid"
            BooleanEquals = true
            Next         = "RunGlueETL"
          }
        ]
        Default = "ValidationFailed"
      }
      RunGlueETL = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.etl_job.name
        }
        Next = "PipelineSucceeded"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "PipelineFailed"
          }
        ]
      }
      PipelineSucceeded = {
        Type = "Succeed"
      }
      ValidationFailed = {
        Type  = "Fail"
        Error = "CSVValidationError"
        Cause = "Uploaded CSV failed schema/content validation"
      }
      PipelineFailed = {
        Type  = "Fail"
        Error = "GlueETLJobError"
        Cause = "Glue ETL job run failed"
      }
    }
  })
}

resource "aws_sfn_state_machine" "etl_pipeline" {
  name       = "${var.project_name}-pipeline"
  role_arn   = aws_iam_role.step_functions.arn
  definition = local.state_machine_definition
  type       = "STANDARD"
}
