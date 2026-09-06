"""
employees_csv_validator.py

Triggered by an S3 PUT event whenever a new CSV lands in raw/*.csv.
Validates basic structural integrity of the file, then kicks off the
Step Functions state machine that runs the Glue ETL job.

Runtime: Python 3.12
Trigger: S3 ObjectCreated event on prefix "raw/", suffix ".csv"
"""

import csv
import io
import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
sfn = boto3.client("stepfunctions")

REQUIRED_COLUMNS = {"emp_id", "name", "department", "salary", "join_date"}
STATE_MACHINE_ARN = os.environ.get("STATE_MACHINE_ARN", "")


def validate_csv(bucket: str, key: str) -> dict:
    """Download the object and check it has the expected columns and at
    least one data row. Returns a small validation report."""
    obj = s3.get_object(Bucket=bucket, Key=key)
    body = obj["Body"].read().decode("utf-8")

    reader = csv.DictReader(io.StringIO(body))
    header = set(reader.fieldnames or [])

    missing_columns = REQUIRED_COLUMNS - header
    rows = list(reader)

    is_valid = not missing_columns and len(rows) > 0

    return {
        "bucket": bucket,
        "key": key,
        "is_valid": is_valid,
        "row_count": len(rows),
        "missing_columns": sorted(missing_columns),
    }


def handler(event, context):
    record = event["Records"][0]["s3"]
    bucket = record["bucket"]["name"]
    key = record["object"]["key"]

    logger.info("Validating s3://%s/%s", bucket, key)

    report = validate_csv(bucket, key)
    logger.info("Validation report: %s", json.dumps(report))

    if not STATE_MACHINE_ARN:
        logger.warning("STATE_MACHINE_ARN not set - skipping Step Functions start")
        return report

    sfn.start_execution(
        stateMachineArn=STATE_MACHINE_ARN,
        input=json.dumps(report),
    )

    return report
