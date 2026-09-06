############################################
# Lake Formation: column-level security on the
# "employees" table (hides the salary column)
#
# NOTE (bootstrapping quirk): Lake Formation will refuse these
# resources on a fresh account/region until an admin has been
# registered once via the console (Lake Formation > Administrative
# roles and tasks > Add administrators) or with
# `aws lakeformation put-data-lake-settings`. Terraform cannot grant
# itself that first admin permission, so this is a one-time manual
# step before `terraform apply`. Also note the "employees" table
# itself is created by aws_glue_crawler.employees at crawl time, not
# by Terraform, so the crawler must have run at least once before
# this filter can be created successfully.
############################################

data "aws_caller_identity" "current" {}

resource "aws_lakeformation_resource" "data_lake" {
  arn = aws_s3_bucket.data_lake.arn
}

resource "aws_lakeformation_data_cells_filter" "hide_salary" {
  table_data {
    database_name    = aws_glue_catalog_database.data_lake.name
    table_catalog_id = data.aws_caller_identity.current.account_id
    table_name       = "employees"
    name             = "hide-salary"

    # Expose every employees column except salary. column_wildcard +
    # excluded_column_names keeps this correct automatically if columns
    # are added later, instead of hardcoding the full column list
    # (emp_id, name, department, salary, join_date, salary_grade,
    # processed_timestamp) and having to remember to update it.
    column_wildcard {
      excluded_column_names = ["salary"]
    }

    row_filter {
      all_rows_wildcard {}
    }
  }

  depends_on = [aws_lakeformation_resource.data_lake]
}
