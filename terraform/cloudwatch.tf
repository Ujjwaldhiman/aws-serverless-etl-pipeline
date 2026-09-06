############################################
# CloudWatch alarm: Lambda validator errors
############################################

resource "aws_cloudwatch_metric_alarm" "csv_validator_errors" {
  alarm_name          = "${var.project_name}-csv-validator-errors"
  alarm_description   = "Triggers when the ${var.project_name} CSV validator Lambda reports one or more errors in a single evaluation period."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.csv_validator.function_name
  }

  alarm_actions = [aws_sns_topic.lambda_errors.arn]
  ok_actions    = [aws_sns_topic.lambda_errors.arn]
}
