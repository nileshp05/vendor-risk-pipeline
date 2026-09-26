CREATE OR REPLACE PROCEDURE `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.sp_build_vendor_score_fact`(p_report_month DATE)
BEGIN
    DECLARE v_start_time TIMESTAMP;
    DECLARE v_status STRING DEFAULT 'SUCCESS';
    DECLARE v_error_message STRING DEFAULT NULL;
    DECLARE v_inserted_count INT64 DEFAULT 0;

    SET v_start_time = CURRENT_TIMESTAMP();

    BEGIN
        -- 1. Idempotent deletion of existing records for the report month
        DELETE FROM `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.VendorScoreFact`
        WHERE report_month = p_report_month;

        -- 2. Calculate and insert vendor scores into the fact table
        INSERT INTO `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.VendorScoreFact`
        (
            vendor_id,
            report_month,
            metric_id,
            metric_name,
            metric_value,
            metric_score,
            metric_weight,
            weighted_score,
            vendor_risk_percentage,
            load_timestamp
        )
        WITH metric_scores AS
        (
            SELECT
                vendor_id,
                report_month,
                metric_id,
                metric_name,
                metric_value,
                metric_weight,
                CASE
                    WHEN metric_value >= 80 THEN 100
                    WHEN metric_value >= 60 THEN 70
                    WHEN metric_value >= 40 THEN 40
                    ELSE 10
                END AS metric_score
            FROM `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.AllMetricValues`
            WHERE report_month = p_report_month
        ),
        vendor_scores AS
        (
            SELECT
                vendor_id,
                SUM(metric_score * metric_weight / 100) AS vendor_risk_percentage
            FROM metric_scores
            GROUP BY vendor_id
        )
        SELECT
            m.vendor_id,
            m.report_month,
            m.metric_id,
            m.metric_name,
            m.metric_value,
            m.metric_score,
            m.metric_weight,
            m.metric_score * m.metric_weight / 100 AS weighted_score,
            v.vendor_risk_percentage,
            CURRENT_TIMESTAMP()
        FROM metric_scores m
        JOIN vendor_scores v
        USING (vendor_id);

        -- 3. Capture inserted record count from target table
        SET v_inserted_count = (
            SELECT COUNT(*)
            FROM `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.VendorScoreFact`
            WHERE report_month = p_report_month
        );

    EXCEPTION WHEN ERROR THEN
        -- Capture SQL execution or runtime failures
        SET v_status = 'FAILED';
        SET v_error_message = @@error.message;
    END;

    -- 4. Log Audit Record (Executes regardless of PASS/FAIL status)
    CALL `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sp_log_audit`(
        'RUN_' || FORMAT_DATE('%Y%m%d', p_report_month),
        CURRENT_DATE(),
        p_report_month,
        'GOLD_BUILD',
        'VENDOR_SCORE_FACT',
        v_status,
        v_inserted_count,
        v_error_message,
        v_start_time,
        CURRENT_TIMESTAMP()
    );

    -- 5. Propagate error to orchestration layer if execution failed
    IF v_status = 'FAILED' THEN
        ERROR(v_error_message);
    END IF;

END;