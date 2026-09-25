CREATE OR REPLACE PROCEDURE `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sp_calculate_derived_risk`(p_report_month DATE)
BEGIN

    DELETE FROM
    `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.vendor_risk_derived`

    WHERE report_month = p_report_month;


    INSERT INTO
    `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.vendor_risk_derived`

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

        -- Example financial risk
        100 - s.financial_score
            AS financial_risk,

        -- Example reputation risk
        100 - s.reputation_score
            AS reputational_risk,

        -- Example EHS risk
        100 - s.ehs_score
            AS ehs_risk,

        CURRENT_TIMESTAMP()

    FROM
    `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sqlserver_vendor_metrics` s

    WHERE
        DATE_TRUNC(s.report_date, MONTH) = p_report_month;

    -- Add this right before END;
    CALL `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sp_log_audit`(
        'RUN_' || FORMAT_DATE('%Y%m%d', p_report_month),
        CURRENT_DATE(),
        p_report_month,
        'GOLD_BUILD',
        'DERIVED_RISK',
        'SUCCESS',
        (SELECT COUNT(*) FROM `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.AllMetricValues` WHERE report_month = p_report_month),
        NULL,
        CURRENT_TIMESTAMP(),
        CURRENT_TIMESTAMP()
    );

END;