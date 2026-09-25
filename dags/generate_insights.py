import os
import re
from datetime import date, datetime
from google.cloud import bigquery
import vertexai
from vertexai.generative_models import GenerativeModel

PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "third-party-vendor-risk-pl-dev")
LOCATION = os.environ.get("VERTEX_LOCATION", "us-central1")


def parse_gemini_response(text: str):
    """Parses Risk Event, Risk Area, and Risk Mitigation sections from text."""
    event_match = re.search(r"Risk Event:\s*(.*?)(?=\nRisk Area:|\nRisk Mitigation:|$)", text, re.DOTALL)
    area_match = re.search(r"Risk Area:\s*(.*?)(?=\nRisk Mitigation:|$)", text, re.DOTALL)
    mitigation_match = re.search(r"Risk Mitigation:\s*(.*?)$", text, re.DOTALL)

    risk_event = event_match.group(1).strip() if event_match else ""
    risk_area = area_match.group(1).strip() if area_match else ""
    risk_mitigation = mitigation_match.group(1).strip() if mitigation_match else ""

    return risk_event, risk_area, risk_mitigation


def main():
    vertexai.init(project=PROJECT_ID, location=LOCATION)
    model = GenerativeModel("gemini-2.5-flash")
    bq = bigquery.Client(project=PROJECT_ID)

    current_report_month = date.today().replace(day=1).strftime("%Y-%m-%d")

    # 1. Clear existing insights for the current month to ensure idempotency
    delete_query = f"""
    DELETE FROM `{PROJECT_ID}.cis_thirdparty_gold_layer.RiskInsight`
    WHERE report_month = DATE_TRUNC(CURRENT_DATE(), MONTH);
    """
    bq.query(delete_query).result()

    # 2. Query metric values exceeding risk thresholds
    query = f"""
    SELECT
        v.vendor_id,
        v.metric_name,
        v.metric_value,
        t.threshold_value,
        t.risk_area,
        t.mitigation_guidance
    FROM
        `{PROJECT_ID}.cis_thirdparty_gold_layer.AllMetricValues` v
    JOIN
        `{PROJECT_ID}.cis_thirdparty_gold_layer.RiskThreshold` t
    ON
        v.metric_id = t.metric_id
    WHERE
        v.report_month = DATE_TRUNC(CURRENT_DATE(), MONTH)
        AND v.metric_value >= t.threshold_value
    """

    rows = bq.query(query).result()
    rows_to_insert = []

    # 3. Generate insights via Vertex AI
    for row in rows:
        prompt = f"""
You are generating a vendor risk insight.

Use ONLY the evidence supplied below.

Vendor:
{row.vendor_id}

Risk metric:
{row.metric_name}

Observed value:
{row.metric_value}

Threshold:
{row.threshold_value}

Risk area:
{row.risk_area}

Existing mitigation guidance:
{row.mitigation_guidance}

Return exactly three sections:

Risk Event:
<short factual statement>

Risk Area:
<risk area>

Risk Mitigation:
<practical mitigation>

Do not invent facts.
Do not invent incidents.
Do not claim information not supplied above.
"""
        response = model.generate_content(prompt)
        risk_event, risk_area, risk_mitigation = parse_gemini_response(response.text)

        rows_to_insert.append({
            "vendor_id": row.vendor_id,
            "report_month": current_report_month,
            "risk_event": risk_event,
            "risk_area": risk_area,
            "risk_mitigation": risk_mitigation,
            "generated_timestamp": datetime.utcnow().isoformat()
        })

        print(f"Generated risk insight for Vendor: {row.vendor_id}")

    # 4. Stream rows to BigQuery
    if rows_to_insert:
        table_id = f"{PROJECT_ID}.cis_thirdparty_gold_layer.RiskInsight"
        errors = bq.insert_rows_json(table_id, rows_to_insert)
        if not errors:
            print(f"Successfully inserted {len(rows_to_insert)} rows into {table_id}.")
        else:
            print(f"Errors occurred while inserting rows: {errors}")
    else:
        print("No high-risk metrics exceeded threshold limits for this month.")


if __name__ == "__main__":
    main()