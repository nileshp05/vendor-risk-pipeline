CREATE OR REPLACE PROCEDURE `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sp_data_quality`(p_report_month DATE)
BEGIN
    DECLARE duplicate_count INT64 DEFAULT 0;
    DECLARE vendor_count INT64 DEFAULT 0;
    DECLARE metric_count INT64 DEFAULT 0;
    DECLARE v_status STRING DEFAULT 'SUCCESS';
    DECLARE v_error_message STRING DEFAULT NULL;
    DECLARE v_start_time TIMESTAMP;

    SET v_start_time = CURRENT_TIMESTAMP();

    BEGIN
        -- 1. Calculate Data Quality Metrics
        SET duplicate_count = (
            SELECT COUNT(*)
            FROM (
                SELECT
                    vendor_id,
                    metric_id
                FROM `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.AllMetricValues`
                WHERE report_month = p_report_month
                GROUP BY vendor_id, metric_id
                HAVING COUNT(*) > 1
            )
        );

        SET vendor_count = (
            SELECT COUNT(DISTINCT vendor_id)
            FROM `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.VendorScoreFact`
            WHERE report_month = p_report_month
        );

        SET metric_count = (
            SELECT COUNT(*)
            FROM `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.AllMetricValues`
            WHERE report_month = p_report_month
        );

        -- 2. Validate Data Quality Rules & Collect Error Details
        IF duplicate_count > 0 THEN
            SET v_status = 'FAILED';
            SET v_error_message = CONCAT(IFNULL(v_error_message || '; ', ''), 'Duplicate vendor/metric records found (Count: ', CAST(duplicate_count AS STRING), ')');
        END IF;

        IF vendor_count = 0 THEN
            SET v_status = 'FAILED';
            SET v_error_message = CONCAT(IFNULL(v_error_message || '; ', ''), 'No vendors found in VendorScoreFact for report month');
        END IF;

        IF metric_count = 0 THEN
            SET v_status = 'FAILED';
            SET v_error_message = CONCAT(IFNULL(v_error_message || '; ', ''), 'No metrics found in AllMetricValues for report month');
        END IF;

    EXCEPTION WHEN ERROR THEN
        -- Catch runtime/system SQL errors
        SET v_status = 'FAILED';
        SET v_error_message = @@error.message;
    END;

    -- 3. Log Audit Record (Executes regardless of PASS/FAIL)
    CALL `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sp_log_audit`(
        'RUN_' || FORMAT_DATE('%Y%m%d', p_report_month),
        CURRENT_DATE(),
        p_report_month,
        'GOLD_BUILD',
        'DATA_QUALITY',
        v_status,
        metric_count,
        v_error_message,
        v_start_time,
        CURRENT_TIMESTAMP()
    );

    -- 4. Fail Procedure Execution if Data Quality Checks Failed
    IF v_status = 'FAILED' THEN
        ERROR(v_error_message);
    END IF;

END;