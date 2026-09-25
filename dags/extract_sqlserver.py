import csv
import io
import os
from datetime import datetime, timezone

import pyodbc
from google.cloud import storage
from google.cloud import secretmanager


PROJECT_ID = os.environ["GCP_PROJECT_ID"]
BUCKET_NAME = os.environ["RAW_BUCKET"]
SECRET_ID = os.environ["SQLSERVER_SECRET_ID"]


def get_secret(project_id, secret_id):
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")


def upload_to_gcs(bucket_name, blob_name, content):
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(blob_name)
    blob.upload_from_string(content, content_type="text/csv")


def main():
    # Use Airflow's logical date if passed, otherwise fallback to current UTC time
    execution_date_str = os.getenv("EXECUTION_DATE")
    if execution_date_str:
        run_timestamp = datetime.fromisoformat(execution_date_str)
    else:
        run_timestamp = datetime.now(timezone.utc)

    connection_string = get_secret(PROJECT_ID, SECRET_ID)

    if "TrustServerCertificate" not in connection_string:
        connection_string = connection_string.rstrip(";") + ";TrustServerCertificate=yes;"

    connection = pyodbc.connect(connection_string, timeout=60)
    cursor = connection.cursor()

    cursor.execute(
        """
        SELECT
            vendor_id,
            vendor_name,
            security_score,
            financial_score,
            reputation_score,
            ehs_score,
            compliance_score,
            report_date
        FROM VendorRiskMetrics
        WHERE report_date >= DATEADD(
            MONTH,
            DATEDIFF(MONTH, 0, GETDATE()),
            0
        )
        """
    )

    columns = [column[0] for column in cursor.description]
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(columns)

    for row in cursor.fetchall():
        writer.writerow(row)

    cursor.close()
    connection.close()

    date_path = run_timestamp.strftime("%Y/%m/%d")
    timestamp = run_timestamp.strftime("%Y%m%d_%H%M%S")

    blob_name = f"raw/sqlserver/{date_path}/vendor_metrics_{timestamp}.csv"

    upload_to_gcs(BUCKET_NAME, blob_name, output.getvalue())

    print(f"SQL Server extraction successful: gs://{BUCKET_NAME}/{blob_name}")


if __name__ == "__main__":
    main()