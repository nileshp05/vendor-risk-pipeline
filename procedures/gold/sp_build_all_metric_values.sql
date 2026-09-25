CREATE OR REPLACE PROCEDURE `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.sp_build_all_metric_values`(p_report_month DATE)
BEGIN

    DELETE FROM
    `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.AllMetricValues`
    WHERE report_month = p_report_month;


    INSERT INTO
    `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.AllMetricValues`
    (
        vendor_id,
        report_month,
        metric_id,
        metric_name,
        metric_value,
        metric_weight,
        load_timestamp
    )

    SELECT
        s.vendor_id,
        p_report_month,
        1,
        'Security Risk',
        100 - s.security_score,
        20,
        CURRENT_TIMESTAMP()
    FROM
    `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sqlserver_vendor_metrics` s
    WHERE DATE_TRUNC(s.report_date, MONTH) = p_report_month


    UNION ALL


    SELECT
        s.vendor_id,
        p_report_month,
        2,
        'Financial Risk',
        d.financial_risk,
        20,
        CURRENT_TIMESTAMP()
    FROM
    `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sqlserver_vendor_metrics` s
    JOIN
    `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.vendor_risk_derived` d
    ON s.vendor_id = d.vendor_id
    AND DATE_TRUNC(s.report_date, MONTH) = d.report_month
    WHERE DATE_TRUNC(s.report_date, MONTH) = p_report_month


    UNION ALL


    SELECT
        s.vendor_id,
        p_report_month,
        3,
        'Reputational Risk',
        d.reputational_risk,
        20,
        CURRENT_TIMESTAMP()
    FROM
    `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sqlserver_vendor_metrics` s
    JOIN
    `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.vendor_risk_derived` d
    ON s.vendor_id = d.vendor_id
    AND DATE_TRUNC(s.report_date, MONTH) = d.report_month
    WHERE DATE_TRUNC(s.report_date, MONTH) = p_report_month


    UNION ALL


    SELECT
        s.vendor_id,
        p_report_month,
        4,
        'EHS Risk',
        d.ehs_risk,
        20,
        CURRENT_TIMESTAMP()
    FROM
    `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sqlserver_vendor_metrics` s
    JOIN
    `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.vendor_risk_derived` d
    ON s.vendor_id = d.vendor_id
    AND DATE_TRUNC(s.report_date, MONTH) = d.report_month
    WHERE DATE_TRUNC(s.report_date, MONTH) = p_report_month


    UNION ALL


    SELECT
        a.vendor_id,
        p_report_month,
        5,
        'Operational Risk',
        100 - a.availability_score,
        20,
        CURRENT_TIMESTAMP()
    FROM
    `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.api_vendor_metrics` a
    WHERE a.report_month = p_report_month;

    -- Add this right before END;
    CALL `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sp_log_audit`(
        'RUN_' || FORMAT_DATE('%Y%m%d', p_report_month),
        CURRENT_DATE(),
        p_report_month,
        'GOLD_BUILD',
        'ALL_METRICS',
        'SUCCESS',
        (SELECT COUNT(*) FROM `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.AllMetricValues` WHERE report_month = p_report_month),
        NULL,
        CURRENT_TIMESTAMP(),
        CURRENT_TIMESTAMP()
    );

END;