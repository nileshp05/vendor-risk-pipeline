CREATE OR REPLACE PROCEDURE `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.sp_build_all_metric_values`(p_report_month DATE)
BEGIN
    DECLARE v_start_time TIMESTAMP;
    DECLARE v_status STRING DEFAULT 'SUCCESS';
    DECLARE v_error_message STRING DEFAULT NULL;
    DECLARE v_inserted_count INT64 DEFAULT 0;

    SET v_start_time = CURRENT_TIMESTAMP();

    BEGIN
        -- 1. Idempotent deletion of existing records for the report month
        DELETE FROM `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.AllMetricValues`
        WHERE report_month = p_report_month;

        -- 2. Consolidate and insert metric values across all sources
        INSERT INTO `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.AllMetricValues`
        (
            vendor_id,
            report_month,
            metric_id,
            metric_name,
            metric_value,
            metric_weight,
            load_timestamp
        )

        -- Security Risk
        SELECT
            s.vendor_id,
            p_report_month,
            1,
            'Security Risk',
            100 - s.security_score,
            20,
            CURRENT_TIMESTAMP()
        FROM `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sqlserver_vendor_metrics` s
        WHERE DATE_TRUNC(s.report_date, MONTH) = p_report_month

        UNION ALL

        -- Financial Risk
        SELECT
            s.vendor_id,
            p_report_month,
            2,
            'Financial Risk',
            d.financial_risk,
            20,
            CURRENT_TIMESTAMP()
        FROM `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sqlserver_vendor_metrics` s
        JOIN `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.vendor_risk_derived` d
            ON s.vendor_id = d.vendor_id
            AND DATE_TRUNC(s.report_date, MONTH) = d.report_month
        WHERE DATE_TRUNC(s.report_date, MONTH) = p_report_month

        UNION ALL

        -- Reputational Risk
        SELECT
            s.vendor_id,
            p_report_month,
            3,
            'Reputational Risk',
            d.reputational_risk,
            20,
            CURRENT_TIMESTAMP()
        FROM `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sqlserver_vendor_metrics` s
        JOIN `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.vendor_risk_derived` d
            ON s.vendor_id = d.vendor_id
            AND DATE_TRUNC(s.report_date, MONTH) = d.report_month
        WHERE DATE_TRUNC(s.report_date, MONTH) = p_report_month

        UNION ALL

        -- EHS Risk
        SELECT
            s.vendor_id,
            p_report_month,
            4,
            'EHS Risk',
            d.ehs_risk,
            20,
            CURRENT_TIMESTAMP()
        FROM `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sqlserver_vendor_metrics` s
        JOIN `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.vendor_risk_derived` d
            ON s.vendor_id = d.vendor_id
            AND DATE_TRUNC(s.report_date, MONTH) = d.report_month
        WHERE DATE_TRUNC(s.report_date, MONTH) = p_report_month

        UNION ALL

        -- Operational Risk
        SELECT
            a.vendor_id,
            p_report_month,
            5,
            'Operational Risk',
            100 - a.availability_score,
            20,
            CURRENT_TIMESTAMP()
        FROM `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.api_vendor_metrics` a
        WHERE a.report_month = p_report_month;

        -- 3. Capture inserted record count from target table
        SET v_inserted_count = (
            SELECT COUNT(*)
            FROM `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.AllMetricValues`
            WHERE report_month = p_report_month
        );

    EXCEPTION WHEN ERROR THEN
        -- Trap runtime SQL or execution errors
        SET v_status = 'FAILED';
        SET v_error_message = @@error.message;
    END;

    -- 4. Log Audit Record (Runs regardless of PASS/FAIL status)
    CALL `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sp_log_audit`(
        'RUN_' || FORMAT_DATE('%Y%m%d', p_report_month),
        CURRENT_DATE(),
        p_report_month,
        'GOLD_BUILD',
        'ALL_METRICS',
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