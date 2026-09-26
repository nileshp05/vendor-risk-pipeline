CREATE OR REPLACE PROCEDURE `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sp_calculate_derived_risk`(p_report_month DATE)
BEGIN
    DECLARE v_start_time TIMESTAMP;
    DECLARE v_status STRING DEFAULT 'SUCCESS';
    DECLARE v_error_message STRING DEFAULT NULL;
    DECLARE v_inserted_count INT64 DEFAULT 0;

    SET v_start_time = CURRENT_TIMESTAMP();

    BEGIN
        -- 1. Idempotent deletion of existing derived risk data for the report month
        DELETE FROM `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.vendor_risk_derived`
        WHERE report_month = p_report_month;

        -- 2. Populate derived risk metrics
        INSERT INTO `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.vendor_risk_derived`
        (
            vendor_id,
            report_month,
            financial_risk,
            reputational_risk,
            ehs_risk,
            load_timestamp
        )
        SELECT
            s.vendor_id,
            p_report_month,
            100 - s.financial_score AS financial_risk,
            100 - s.reputation_score AS reputational_risk,
            100 - s.ehs_score AS ehs_risk,
            CURRENT_TIMESTAMP()
        FROM `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sqlserver_vendor_metrics` s
        WHERE DATE_TRUNC(s.report_date, MONTH) = p_report_month;

        -- 3. Capture inserted record count
        SET v_inserted_count = (
            SELECT COUNT(*)
            FROM `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.vendor_risk_derived`
            WHERE report_month = p_report_month
        );

    EXCEPTION WHEN ERROR THEN
        -- Capture SQL or runtime execution failures
        SET v_status = 'FAILED';
        SET v_error_message = @@error.message;
    END;

    -- 4. Log Audit Record (Runs for both SUCCESS and FAILED status)
    CALL `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sp_log_audit`(
        'RUN_' || FORMAT_DATE('%Y%m%d', p_report_month),
        CURRENT_DATE(),
        p_report_month,
        'GOLD_BUILD',
        'DERIVED_RISK',
        v_status,
        v_inserted_count,
        v_error_message,
        v_start_time,
        CURRENT_TIMESTAMP()
    );

    -- 5. Propagate error to pipeline orchestration tools if execution failed
    IF v_status = 'FAILED' THEN
        ERROR(v_error_message);
    END IF;

END;