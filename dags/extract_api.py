import json
import os
from datetime import datetime, timezone
import requests
from google.cloud import secretmanager, storage
from dotenv import load_dotenv

# Load .env file for manual terminal testing
load_dotenv()

PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "third-party-vendor-risk-pl-dev")
BUCKET_NAME = os.environ.get("RAW_BUCKET")
API_URL = os.environ.get("API_URL", "https://my-first-docker-git-953400689956.us-central1.run.app/vendor-risk")
SECRET_ID = os.environ.get("API_SECRET_ID", "api-credentials-secret")
EXECUTION_DATE_ENV = os.environ.get("EXECUTION_DATE")


def get_secret(project_id, secret_id):
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")


def upload_to_gcs(bucket_name, blob_name, data):
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(blob_name)
    blob.upload_from_string(data, content_type="application/json")


def main():
    if not BUCKET_NAME:
        raise ValueError("RAW_BUCKET environment variable is missing. Check your .env or Airflow configuration.")

    # 1. Fetch API key from Secret Manager
    api_key = get_secret(PROJECT_ID, SECRET_ID)

    # 2. Call Cloud Run API
    response = requests.get(
        API_URL,
        headers={"x-api-key": api_key},
        timeout=60
    )
    response.raise_for_status()
    payload = response.json()

    # 3. Handle execution timestamp (from Airflow logical_date or current UTC)
    if EXECUTION_DATE_ENV:
        run_timestamp = datetime.fromisoformat(EXECUTION_DATE_ENV)
    else:
        run_timestamp = datetime.now(timezone.utc)

    date_path = run_timestamp.strftime("%Y/%m/%d")
    timestamp_str = run_timestamp.strftime("%Y%m%d_%H%M%S")

    blob_name = f"raw/api/{date_path}/vendor_risk_{timestamp_str}.json"

    # 4. Format payload into Newline-Delimited JSON (NDJSON) for BigQuery load_api operator
    report_date = payload.get("report_date")
    records = payload.get("records", [])

    ndjson_lines = []
    for record in records:
        record["report_date"] = report_date
        ndjson_lines.append(json.dumps(record))

    ndjson_content = "\n".join(ndjson_lines)

    # 5. Upload to GCS
    upload_to_gcs(BUCKET_NAME, blob_name, ndjson_content)

    print(f"API extraction successful: gs://{BUCKET_NAME}/{blob_name}")


if __name__ == "__main__":
    main()