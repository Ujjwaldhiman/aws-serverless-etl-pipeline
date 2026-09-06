"""
run_and_capture_evidence.py

Runs the full pipeline end-to-end against your deployed AWS stack and
saves timestamped, verifiable proof of the run into ./evidence/ -
execution details, Glue job run stats, and real Athena query results,
all pulled directly from the AWS APIs (not hand-typed).

Usage:
    pip install boto3
    python run_and_capture_evidence.py --bucket <your-bucket-name> --region ap-south-1

What this automates:
    1. Uploads the sample CSV to raw/, which triggers the real pipeline
       (S3 -> Lambda -> Step Functions -> Glue -> S3)
    2. Detects the resulting Step Functions execution and polls it
       until it finishes
    3. Pulls the Glue job run's stats (duration, DPU-hours, state)
    4. Runs a real Athena query against the freshly-processed table
       and saves the actual result rows
    5. Writes everything to evidence/run_<timestamp>/ as JSON + a
       human-readable summary

What this does NOT automate (do this part yourself, ~2 min):
    - Screenshotting the Step Functions execution graph in the console
    - Screenshotting the Athena query editor with results showing
    These are quick to grab manually and pair well with the JSON
    evidence this script produces - the combination of "here's the
    raw API response" + "here's what it looked like" is stronger
    proof than either alone.
"""

import argparse
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import boto3

PROJECT_NAME = "employee-etl"
GLUE_DATABASE = f"{PROJECT_NAME.replace('-', '_')}_catalog"
REPO_ROOT = Path(__file__).parent.parent
SAMPLE_CSV = REPO_ROOT / "sample_data" / "employees.csv"


def upload_sample_csv(s3, bucket: str) -> str:
    key = "raw/employees.csv"
    print(f"Uploading {SAMPLE_CSV} to s3://{bucket}/{key} ...")
    s3.upload_file(str(SAMPLE_CSV), bucket, key)
    return key


def find_new_execution(sfn, state_machine_arn: str, after: datetime, timeout_s: int = 60):
    print("Waiting for the Step Functions execution to start ...")
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        resp = sfn.list_executions(stateMachineArn=state_machine_arn, maxResults=5)
        for execution in resp.get("executions", []):
            if execution["startDate"].replace(tzinfo=timezone.utc) >= after:
                return execution["executionArn"]
        time.sleep(3)
    raise TimeoutError("No new Step Functions execution appeared - check the S3 trigger and Lambda logs.")


def wait_for_execution(sfn, execution_arn: str, timeout_s: int = 180) -> dict:
    print(f"Polling execution: {execution_arn}")
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        desc = sfn.describe_execution(executionArn=execution_arn)
        if desc["status"] != "RUNNING":
            return desc
        time.sleep(5)
    raise TimeoutError("Execution did not finish within timeout.")


def get_latest_glue_run(glue, job_name: str) -> dict:
    resp = glue.get_job_runs(JobName=job_name, MaxResults=1)
    runs = resp.get("JobRuns", [])
    return runs[0] if runs else {}


def run_athena_query(athena, database: str, query: str, output_location: str) -> list:
    print(f"Running Athena query: {query.strip()}")
    start = athena.start_query_execution(
        QueryString=query,
        QueryExecutionContext={"Database": database},
        ResultConfiguration={"OutputLocation": output_location},
    )
    query_id = start["QueryExecutionId"]

    while True:
        status = athena.get_query_execution(QueryExecutionId=query_id)
        state = status["QueryExecution"]["Status"]["State"]
        if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break
        time.sleep(2)

    if state != "SUCCEEDED":
        reason = status["QueryExecution"]["Status"].get("StateChangeReason", "unknown")
        raise RuntimeError(f"Athena query {state}: {reason}")

    results = athena.get_query_results(QueryExecutionId=query_id)
    rows = [
        [col.get("VarCharValue", "") for col in row["Data"]]
        for row in results["ResultSet"]["Rows"]
    ]
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", required=True, help="Data lake S3 bucket name")
    parser.add_argument("--region", default="ap-south-1")
    parser.add_argument(
        "--state-machine-arn",
        required=True,
        help="Output of: terraform output -raw state_machine_arn",
    )
    parser.add_argument(
        "--glue-job-name",
        required=True,
        help="Output of: terraform output -raw glue_job_name",
    )
    args = parser.parse_args()

    session = boto3.Session(region_name=args.region)
    s3 = session.client("s3")
    sfn = session.client("stepfunctions")
    glue = session.client("glue")
    athena = session.client("athena")

    run_started_at = datetime.now(timezone.utc)
    evidence_dir = REPO_ROOT / "evidence" / run_started_at.strftime("run_%Y%m%dT%H%M%SZ")
    evidence_dir.mkdir(parents=True, exist_ok=True)

    # 1. Trigger the pipeline
    upload_sample_csv(s3, args.bucket)

    # 2. Find and wait for the execution
    execution_arn = find_new_execution(sfn, args.state_machine_arn, run_started_at)
    execution_result = wait_for_execution(sfn, execution_arn)
    (evidence_dir / "step_functions_execution.json").write_text(
        json.dumps(execution_result, indent=2, default=str)
    )
    print(f"Execution finished with status: {execution_result['status']}")

    # 3. Glue job run stats
    glue_run = get_latest_glue_run(glue, args.glue_job_name)
    (evidence_dir / "glue_job_run.json").write_text(json.dumps(glue_run, indent=2, default=str))

    # 4. Real Athena query against the freshly-processed data
    athena_output = f"s3://{args.bucket}/athena-results/"
    rows = run_athena_query(
        athena,
        GLUE_DATABASE,
        "SELECT department, COUNT(*) AS headcount, ROUND(AVG(salary)) AS avg_salary "
        "FROM employees GROUP BY department ORDER BY avg_salary DESC;",
        athena_output,
    )
    (evidence_dir / "athena_query_result.json").write_text(json.dumps(rows, indent=2))

    # 5. Human-readable summary
    summary = f"""# Pipeline Run Evidence

Run started (UTC): {run_started_at.isoformat()}
Step Functions execution: {execution_arn}
Final status: {execution_result['status']}
Glue job run ID: {glue_run.get('Id', 'n/a')}
Glue job state: {glue_run.get('JobRunState', 'n/a')}
Glue execution time (s): {glue_run.get('ExecutionTime', 'n/a')}

## Athena query result (department, headcount, avg_salary)
{chr(10).join(str(r) for r in rows)}

Raw API responses backing this summary are in the JSON files in this
same folder - step_functions_execution.json, glue_job_run.json,
athena_query_result.json.
"""
    (evidence_dir / "RUN_SUMMARY.md").write_text(summary)

    print(f"\nDone. Evidence saved to: {evidence_dir}")
    print("Now grab two screenshots to pair with this: the Step Functions")
    print("execution graph, and the Athena query editor with results showing.")


if __name__ == "__main__":
    main()
