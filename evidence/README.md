# Evidence — pipeline running in AWS

These screenshots were captured while building and running this pipeline
hands-on in the AWS Console (Mumbai / ap-south-1, account 7298-5959-9023).
They show each stage of the pipeline actually executing against real AWS
services.

> **Note on this repo vs. these screenshots:** the pipeline was originally
> built interactively in the AWS Console. The Terraform and application
> code in this repository is a clean, version-controlled reconstruction of
> that same architecture, so it can be deployed reproducibly by anyone.
> The resource names in the code (`employees-etl-pipeline`,
> `employees-etl-job`, the `raw/processed/curated` layout) match what's
> shown below.

## What each screenshot shows

| File | What it proves |
|---|---|
| `01_stepfunctions_all_succeeded.png` | The `employees-etl-pipeline` Step Functions execution completing end-to-end — `ValidateCSV → CheckValidation → RunGlueETL → PipelineSucceeded`, every state green. |
| `02_athena_query_results.png` | An Athena query returning the processed data, including the two columns the ETL job derives: `salary_grade` and `processed_timestamp`. Query completed in 462 ms, 0.46 KB scanned. |
| `03_s3_raw_processed_curated.png` | The S3 data lake bucket showing the three-zone layout (`raw/`, `processed/`, `curated/`) with source data present. |
| `04_glue_job_succeeded.png` | The `employees-etl-job` Glue run: **Succeeded**, 1 min 5 sec, 2× G.1X workers, Glue 5.1, 0.036 DPU-hours. |
| `06_billing_zero_spend.png` | Billing dashboard confirming the entire build ran within the free plan / credits — estimated grand total USD 0.00, highest single-service spend USD 0.02. |

## Reproducing this yourself

See the root `README.md` for full deploy instructions. In short:
`terraform apply` provisions the stack, then
`scripts/run_and_capture_evidence.py` runs the pipeline and saves a fresh
set of execution records (Step Functions status, Glue run stats, and
actual Athena results) into a timestamped folder here.
