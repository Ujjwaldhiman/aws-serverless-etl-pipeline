-- Sample queries against the Glue-cataloged `employees` table
-- Query results configured to write to s3://<your-bucket-name>/athena-results/

-- Basic scan
SELECT * FROM employees LIMIT 10;

-- Average salary and headcount by department
SELECT
    department,
    COUNT(*)          AS headcount,
    ROUND(AVG(salary)) AS avg_salary
FROM employees
GROUP BY department
ORDER BY avg_salary DESC;

-- Distribution across derived salary grades
SELECT
    salary_grade,
    COUNT(*) AS employee_count
FROM employees
GROUP BY salary_grade
ORDER BY salary_grade;

-- Employees above a salary threshold, most recently processed first
SELECT emp_id, name, department, salary, processed_timestamp
FROM employees
WHERE salary > 85000
ORDER BY processed_timestamp DESC;
