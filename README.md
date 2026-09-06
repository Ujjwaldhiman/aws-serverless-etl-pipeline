# Serverless Employee Data ETL Pipeline on AWS

A fully serverless, event-driven ETL pipeline that validates, transforms, and catalogs employee data for analytics — built entirely with managed AWS services and provisioned via Terraform.

## What it does

A CSV lands in an S3 raw zone → gets automatically validated by Lambda → triggers a Step Functions workflow that runs a Glue ETL job to enrich and convert the data to Parquet → the result is cataloged and queryable in Athena within minutes, with zero servers to manage.

## Architecture

```
                    ┌─────────────────┐
   CSV Upload  ───▶ │  S3 (raw/)       │
                    └────────┬─────────┘
                             │ S3 Event Trigger
                             ▼
                    ┌─────────────────┐        ┌───────────────────┐
                    │ Lambda           │──────▶ │ CloudWatch Alarm   │
                    │ CSV Validator    │        │ (on error) ──▶ SNS │
                    └────────┬─────────┘        └───────────────────┘
                             │ starts execution
                             ▼
                    ┌───────────────────────────────────────┐
                    │  Step Functions: employees-etl-pipeline│
                    │                                        │
                    │  ValidateCSV ─▶ CheckValidation         │
                    │       │passed         │failed           │
                    │       ▼                ▼                │
                    │  RunGlueETL      PipelineFailed          │
                    │       │                                  │
                    │       ▼                                  │
                    │  PipelineSucceeded                        │
                    └───────────────┬───────────────────────┘
                                    ▼
                    ┌─────────────────────────────┐
                    │ Glue ETL Job                 │
                    │ - adds salary_grade (A/B/C)  │
                    │ - adds processed_timestamp   │
                    │ - writes Parquet             │
                    └────────────┬─────────────────┘
                                 ▼
                    ┌─────────────────┐      ┌────────────────┐
                    │ S3 (processed/)  │─────▶│ Glue Crawler    │
                    └──────────────────┘      └────────┬────────┘
                                                        ▼
                                               ┌─────────────────┐
                                               │ Glue Data Catalog│
                                               │ (employees table)│
                                               └────────┬─────────┘
                                                         ▼
                                               ┌─────────────────┐
                                               │ Amazon Athena    │
                                               │ (SQL queries)    │
                                               └─────────────────┘
```

## Tech stack

| Layer | Service |
|---|---|
| Storage (data lake) | Amazon S3 (raw / processed / curated zones) |
| Event trigger + validation | AWS Lambda (Python 3.12) |
| Orchestration | AWS Step Functions (Standard workflow) |
| Transformation | AWS Glue ETL (PySpark, 2x G.1X workers) |
| Cataloging | AWS Glue Data Catalog + Crawler |
| Querying | Amazon Athena |
| Monitoring | Amazon CloudWatch (alarms) + SNS |
| Access control | IAM (least-privilege roles per service) |
| Infrastructure as Code | Terraform |

## What the ETL actually does

The Glue job reads raw employee CSVs (`emp_id, name, department, salary, join_date`) and:
1. Derives a `salary_grade` column (A / B / C) based on salary thresholds
2. Adds a `processed_timestamp` column for lineage/auditability
3. Writes the result out as **Parquet** (columnar, compressed — ~4-5x smaller than CSV, and Athena only scans the columns a query needs instead of the whole file)

## Data governance

Column-level security is enforced via **Lake Formation** — a data filter hides the `salary` column from users who shouldn't see compensation data, tested by querying the same table through Athena with and without the filter applied.

## Results / cost

- End-to-end pipeline run: raw CSV → validated → transformed → queryable in Athena in under 2 minutes
- Fully serverless — no infrastructure to patch or scale manually
- Entire dev/test cycle (S3 + Lambda + Glue job runs) cost **under $0.05** thanks to on-demand/serverless pricing — the whole stack is destroyed via `terraform destroy` when not in use
- Failure path is handled explicitly in the state machine (`ValidationFailed → PipelineFailed`) rather than failing silently

## Repo structure

```
terraform/           # Infrastructure as code — deploys the ENTIRE stack:
                      # S3, IAM roles, Lambda, Glue job, Step Functions, SNS
lambda/               # CSV validation function (source of truth - packaged by Terraform)
glue/                 # PySpark ETL job (source of truth - packaged by Terraform)
step_functions/       # Reference copy of the state machine definition
sql/                  # Sample Athena queries
sample_data/          # Small synthetic dataset for testing
scripts/              # End-to-end run + evidence-capture automation
evidence/             # Generated by scripts/run_and_capture_evidence.py - real
                      # execution records proving the pipeline actually ran
```

## How to run it

Everything is automated except two screenshots.

1. `cd terraform && terraform init && terraform apply -var="data_lake_bucket_name=<your-unique-bucket-name>" -var="alert_email=<you@example.com>"` — this alone provisions and wires up the entire stack (S3, IAM, Lambda, Glue job, Step Functions, SNS alerting)
2. `cd .. && python scripts/run_and_capture_evidence.py --bucket <your-unique-bucket-name> --region ap-south-1 --state-machine-arn $(terraform -chdir=terraform output -raw state_machine_arn) --glue-job-name $(terraform -chdir=terraform output -raw glue_job_name)` — uploads the sample CSV, waits for the pipeline to run for real, and saves the execution record, Glue run stats, and actual Athena query results to `evidence/`
3. Manually grab two screenshots — the Step Functions execution graph and the Athena query editor with results — and drop them in `evidence/` alongside the JSON
4. `terraform -chdir=terraform destroy` when done, to avoid ongoing charges

## What I'd improve next

- Add schema validation (not just presence checks) in the Lambda layer using a JSON schema
- Move the Glue job to a bookmark-enabled incremental pattern instead of full reprocessing
- Add a dead-letter queue for failed Step Functions executions
- Parameterize salary grade thresholds instead of hardcoding them

## Notes on this repo

This project was originally built hands-on directly in the AWS Console as part of a structured learning path, then reconstructed here as Infrastructure-as-Code and version-controlled application code for portfolio purposes. Resource names below use placeholders (`<your-bucket-name>` etc.) — replace with your own before deploying, and never commit real AWS account IDs or credentials.

See [`evidence/`](evidence/) for screenshots of the pipeline running in a real AWS account.
