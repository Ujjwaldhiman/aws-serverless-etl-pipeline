"""
employees_etl_job.py

AWS Glue ETL job (PySpark). Reads raw employee CSV data, enriches it with
a derived salary_grade column and a processing timestamp, and writes the
result out as Parquet, partitioned by department, ready for cataloging
and querying via Athena.

Configured to run with 2x G.1X workers - sized for small/medium batch
loads, not for large-scale streaming ingestion.
"""

import sys
from datetime import datetime, timezone

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import StringType

args = getResolvedOptions(sys.argv, ["JOB_NAME", "SOURCE_PATH", "TARGET_PATH"])

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
job = Job(glue_context)
job.init(args["JOB_NAME"], args)

SOURCE_PATH = args["SOURCE_PATH"]  # e.g. s3://<bucket>/raw/employees.csv
TARGET_PATH = args["TARGET_PATH"]  # e.g. s3://<bucket>/processed/employees/


def salary_grade(salary_col):
    """A: >= 80,000  B: 50,000-79,999  C: < 50,000"""
    return (
        F.when(salary_col >= 80000, F.lit("A"))
        .when(salary_col >= 50000, F.lit("B"))
        .otherwise(F.lit("C"))
    )


def run():
    df = (
        spark.read.option("header", "true")
        .option("inferSchema", "true")
        .csv(SOURCE_PATH)
    )

    processed_at = datetime.now(timezone.utc).isoformat()

    enriched = df.withColumn(
        "salary_grade", salary_grade(F.col("salary"))
    ).withColumn(
        "processed_timestamp", F.lit(processed_at).cast(StringType())
    )

    (
        enriched.write.mode("overwrite")
        .partitionBy("department")
        .parquet(TARGET_PATH)
    )

    print(f"Wrote {enriched.count()} rows to {TARGET_PATH}")


run()
job.commit()
