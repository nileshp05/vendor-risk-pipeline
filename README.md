# Sample Third-Party Vendor Risk Assessment Platform & Automated Vendor Risk Insights Generation

I build an end-to-end data engineering and analytics pipeline designed to assess, score, and monitor third-party vendor risks. The platform ingests data from external APIs, PostgreSQL, and SQL Server databases, orchestrates workflows via Apache Airflow (Google Cloud Composer), processes data across BigQuery Medallion layers (Silver & Gold), and exposes analytical insights through Looker. I automated the generation of structured key risk insights using Vertex AI and prompt based python script and exposed on the same Looker dashboard.

---

## 🏗️ Sample Architecture Overview

```text
 REST API / PostgreSQL / SQL Server
                 │
                 ▼
     Google Cloud Composer (Airflow)
                 │
                 ▼
       Google Cloud Storage (GCS)
                 │
                 ▼
        Google BigQuery
          ├── Silver Layer (cis_staging_silver_layer)
          └── Gold Layer   (cis_thirdparty_gold_layer)
                 │
         ┌───────┴───────┐
         ▼               ▼
      Looker         Vertex AI
```

1. **Ingestion:** Data extracted from REST APIs, PostgreSQL, and SQL Server databases using specialized Airflow extraction scripts (`extract_api.py`, `extract_sqlserver.py`).
2. **Storage & Landing:** Raw extracts are dumped into Google Cloud Storage buckets (`thirdparty-vendor-risk-2026-raw-layer`).
3. **Warehouse Processing:** Data is moved from GCS to BigQuery:
   - **Silver Layer (`cis_staging_silver_layer`):** Handles data cleansing, auditing (`sp_log_audit.sql`), quality checks (`sp_data_quality.sql`), and risk calculations (`sp_calculate_derived_risk.sql`).
   - **Gold Layer (`cis_thirdparty_gold_layer`):** Builds core facts and dimensional metrics (`sp_build_vendor_score_fact.sql`, `sp_build_all_metric_values.sql`).
4. **Analytics & AI:**
   - **Looker:** Dashboards and risk reports.
   - **Vertex AI:** Advanced risk insights and ML predictions (`generate_insights.py`).

---

## 📂 Sample Repository Structure

```text
vendor-risk-pipeline/
├── dags/
│   ├── extract_api.py              # Ingests vendor data from REST APIs
│   ├── extract_sqlserver.py        # Extracts records from SQL Server/PostgreSQL
│   ├── generate_insights.py       # Triggers AI/ML insights generation
│   └── vendor_risk_daily_dag.py    # Main Airflow DAG orchestrating daily pipeline execution
├── procedures/
│   ├── silver/
│   │   ├── sp_calculate_derived_risk.sql  # Stored procedure to derive vendor risk scores
│   │   ├── sp_data_quality.sql          # Data quality checks and verification
│   │   └── sp_log_audit.sql             # Audit logging for pipeline tracking
│   └── gold/
│       ├── sp_build_all_metric_values.sql # Builds metric aggregations for reporting
│       └── sp_build_vendor_score_fact.sql # Builds primary vendor score fact table
└── .gitignore
```

---

## ⚙️ Sample Configuration Parameters

The orchestration DAG relies on the following default GCP environment variables:

| Variable | Value | Description |
| :--- | :--- | :--- |
| **`PROJECT_ID`** | `third-party-vendor-risk-pl-dev` | Google Cloud Project ID |
| **`BUCKET_NAME`** | `third-party-vendor-risk-raw-layer` | GCS landing bucket for raw files |
| **`DATASET_SILVER`** | `cis_staging_silver_layer` | Staging/Silver BigQuery dataset |
| **`DATASET_GOLD`** | `cis_thirdparty_gold_layer` | Business/Gold BigQuery dataset |
---

## 🚀 Services Used

* Google Cloud Platform account with BigQuery, Cloud Storage, Vertex AI, and Cloud Composer enabled.
* Python 3.8+.
* Apache Airflow 2.x.
* Secret Manager
* Cloud Build
* Looker
* SQL
* Vertex AI and Prompt Configured Python Script for Key Risk Insight Generation

