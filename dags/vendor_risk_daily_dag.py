from datetime import datetime
import os

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.providers.google.cloud.operators.bigquery import (
    BigQueryInsertJobOperator,
)
from airflow.providers.google.cloud.transfers.gcs_to_bigquery import (
    GCSToBigQueryOperator,
)

# GCP Project & Storage Configurations
PROJECT_ID = "third-party-vendor-risk-pl-dev"
BUCKET_NAME = "thirdparty-vendor-risk-2026-raw-layer"
DATASET_SILVER = "cis_staging_silver_layer"
DATASET_GOLD = "cis_thirdparty_gold_layer"

# Dynamically resolve script paths relative to the DAG file's directory
DAG_DIR = os.path.dirname(os.path.abspath(__file__))
EXTRACT_SQL_SCRIPT_PATH = os.path.join(DAG_DIR, "extract_sqlserver.py")
EXTRACT_API_SCRIPT_PATH = os.path.join(DAG_DIR, "extract_api.py")
GENERATE_INSIGHTS_SCRIPT_PATH = os.path.join(DAG_DIR, "generate_insights.py")

with DAG(
    dag_id="vendor_risk_daily",
    start_date=datetime(2026, 9, 1),
    schedule="0 6 * * *",
    catchup=False,
    tags=["vendor-risk"],
) as dag:

    # --- Task 1a: Extract SQL Server Data to GCS ---
    extract_sqlserver = BashOperator(
        task_id="extract_sqlserver",
        bash_command=f"python3 -u {EXTRACT_SQL_SCRIPT_PATH}",
        env={
            "GCP_PROJECT_ID": PROJECT_ID,
            "RAW_BUCKET": BUCKET_NAME,
            "SQLSERVER_SECRET_ID": "sqlserver-credentials-secret",
            "EXECUTION_DATE": "{{ logical_date.isoformat() }}",
        },
    )

    # --- Task 1b: Load SQL Server Data from GCS into BigQuery ---
    load_sqlserver = GCSToBigQueryOperator(
        task_id="load_sqlserver",
        bucket=BUCKET_NAME,
        source_objects=["raw/sqlserver/{{ logical_date.strftime('%Y/%m/%d') }}/vendor_metrics_*.csv"],
        destination_project_dataset_table=f"{PROJECT_ID}.{DATASET_SILVER}.sqlserver_vendor_metrics",
        source_format="CSV",
        skip_leading_rows=1,
        write_disposition="WRITE_APPEND",
        autodetect=False,
        schema_fields=[
            {"name": "vendor_id", "type": "STRING", "mode": "NULLABLE"},
            {"name": "vendor_name", "type": "STRING", "mode": "NULLABLE"},
            {"name": "security_score", "type": "NUMERIC", "mode": "NULLABLE"},
            {"name": "financial_score", "type": "NUMERIC", "mode": "NULLABLE"},
            {"name": "reputation_score", "type": "NUMERIC", "mode": "NULLABLE"},
            {"name": "ehs_score", "type": "NUMERIC", "mode": "NULLABLE"},
            {"name": "compliance_score", "type": "NUMERIC", "mode": "NULLABLE"},
            {"name": "report_date", "type": "DATE", "mode": "NULLABLE"},
        ],
    )

    # --- Task 2a: Extract API Data to GCS ---
    extract_api = BashOperator(
        task_id="extract_api",
        bash_command=f"python3 -u {EXTRACT_API_SCRIPT_PATH}",
        env={
            "GCP_PROJECT_ID": PROJECT_ID,
            "RAW_BUCKET": BUCKET_NAME,
            "API_URL": "your-api-url-here",  # Replace with your actual API endpoint or use Airflow connection/secret
            "API_SECRET_ID": "api-credentials-secret",
            "EXECUTION_DATE": "{{ logical_date.isoformat() }}",
        },
    )

    # --- Task 2b: Ingest API Data from GCS into BigQuery ---
    load_api = GCSToBigQueryOperator(
        task_id="load_api",
        bucket=BUCKET_NAME,
        source_objects=[f"raw/api/{{{{ logical_date.strftime('%Y/%m/%d') }}}}/vendor_risk_*.json"],
        destination_project_dataset_table=f"{PROJECT_ID}.{DATASET_SILVER}.api_vendor_metrics",
        source_format="NEWLINE_DELIMITED_JSON",
        write_disposition="WRITE_APPEND",
        autodetect=True,
        ignore_unknown_values=True,
        schema_update_options=["ALLOW_FIELD_ADDITION", "ALLOW_FIELD_RELAXATION"],
    )

    # 3. Calculate Derived Risk Procedure
    build_derived_risk = BigQueryInsertJobOperator(
        task_id="build_derived_risk",
        configuration={
            "query": {
                "query": f"""
                    CALL `{PROJECT_ID}.{DATASET_SILVER}.sp_calculate_derived_risk`(
                        DATE_TRUNC(DATE('{{{{ ds }}}}'), MONTH)
                    );
                """,
                "useLegacySql": False,
            }
        },
    )

    # 4. Build Gold Layer Metric Values
    build_all_metrics = BigQueryInsertJobOperator(
        task_id="build_all_metric_values",
        configuration={
            "query": {
                "query": f"""
                    CALL `{PROJECT_ID}.{DATASET_GOLD}.sp_build_all_metric_values`(
                        DATE_TRUNC(DATE('{{{{ ds }}}}'), MONTH)
                    );
                """,
                "useLegacySql": False,
            }
        },
    )

    # 5. Build Gold Layer Vendor Score Fact
    build_vendor_score = BigQueryInsertJobOperator(
        task_id="build_vendor_score",
        configuration={
            "query": {
                "query": f"""
                    CALL `{PROJECT_ID}.{DATASET_GOLD}.sp_build_vendor_score_fact`(
                        DATE_TRUNC(DATE('{{{{ ds }}}}'), MONTH)
                    );
                """,
                "useLegacySql": False,
            }
        },
    )

    # 6. Data Quality Check
    data_quality = BigQueryInsertJobOperator(
        task_id="data_quality",
        configuration={
            "query": {
                "query": f"""
                    CALL `{PROJECT_ID}.{DATASET_SILVER}.sp_data_quality`(
                        DATE_TRUNC(DATE('{{{{ ds }}}}'), MONTH)
                    );
                """,
                "useLegacySql": False,
            }
        },
    )

    # 7. Generate Risk Insights
    generate_risk_insights = BashOperator(
        task_id="generate_risk_insights",
        bash_command=f"""
            export GCP_PROJECT_ID="{PROJECT_ID}" && \
            export VERTEX_LOCATION="us-central1" && \
            python3 -u {GENERATE_INSIGHTS_SCRIPT_PATH}
        """,
    )

    # Execution Flow: Run both extract-and-load tracks in parallel, then proceed downstream
    (
        [
            extract_sqlserver >> load_sqlserver,
            extract_api >> load_api
        ]
        >> build_derived_risk
        >> build_all_metrics
        >> build_vendor_score
        >> data_quality
        >> generate_risk_insights
    )