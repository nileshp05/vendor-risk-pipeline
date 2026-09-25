CREATE OR REPLACE PROCEDURE `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sp_log_audit`(p_run_id STRING, p_process_date DATE, p_process_month DATE, p_pipeline_stage STRING, p_source_name STRING, p_status STRING, p_row_count INT64, p_error_message STRING, p_start_timestamp TIMESTAMP, p_end_timestamp TIMESTAMP)
BEGIN
    INSERT INTO `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.audit_log` (
        run_id,
        process_date,
        process_month,
        pipeline_stage,
        source_name,
        status,
        row_count,
        error_message,
        start_timestamp,
        end_timestamp
    )
    VALUES (
        p_run_id,
        p_process_date,
        p_process_month,
        p_pipeline_stage,
        p_source_name,
        p_status,
        p_row_count,
        p_error_message,
        p_start_timestamp,
        p_end_timestamp
    );
END;