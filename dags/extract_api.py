import json
import os
from datetime import datetime, timezone

import requests
from google.cloud import storage
from google.cloud import secretmanager


PROJECT_ID = os.environ["GCP_PROJECT_ID"]
BUCKET_NAME = os.environ["RAW_BUCKET"]
API_URL = os.environ["API_URL"]
SECRET_ID = "vendor-risk-api-key"


def get_secret(project_id, secret_id):

    client = secretmanager.SecretManagerServiceClient()

    name = (
        f"projects/{project_id}/secrets/"
        f"{secret_id}/versions/latest"
    )

    response = client.access_secret_version(
        request={"name": name}
    )

    return response.payload.data.decode("UTF-8")


def upload_to_gcs(bucket_name, blob_name, data):

    client = storage.Client()

    bucket = client.bucket(bucket_name)

    blob = bucket.blob(blob_name)

    blob.upload_from_string(
        data,
        content_type="application/json"
    )


def main():

    api_key = get_secret(
        PROJECT_ID,
        SECRET_ID
    )

    response = requests.get(
        API_URL,
        headers={
            "x-api-key": api_key
        },
        timeout=60
    )

    response.raise_for_status()

    payload = response.json()

    run_timestamp = datetime.now(
        timezone.utc
    )

    date_path = run_timestamp.strftime(
        "%Y/%m/%d"
    )

    timestamp = run_timestamp.strftime(
        "%Y%m%d_%H%M%S"
    )

    blob_name = (
        f"raw/api/{date_path}/"
        f"vendor_risk_{timestamp}.json"
    )

    upload_to_gcs(
        BUCKET_NAME,
        blob_name,
        json.dumps(payload)
    )

    print(
        f"API extraction successful: "
        f"gs://{BUCKET_NAME}/{blob_name}"
    )


if __name__ == "__main__":
    main()