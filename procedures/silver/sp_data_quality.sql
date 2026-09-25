CREATE OR REPLACE PROCEDURE `third-party-vendor-risk-pl-dev.cis_staging_silver_layer.sp_data_quality`(p_report_month DATE)
BEGIN

    DECLARE duplicate_count INT64;
    DECLARE vendor_count INT64;
    DECLARE metric_count INT64;


    SET duplicate_count = (

        SELECT COUNT(*)

        FROM
        (
            SELECT
                vendor_id,
                metric_id

            FROM
            `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.AllMetricValues`

            WHERE report_month = p_report_month

            GROUP BY
                vendor_id,
                metric_id

            HAVING COUNT(*) > 1
        )
    );


    SET vendor_count = (

        SELECT COUNT(DISTINCT vendor_id)

        FROM
        `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.VendorScoreFact`

        WHERE report_month = p_report_month
    );


    SET metric_count = (

        SELECT COUNT(*)

        FROM
        `third-party-vendor-risk-pl-dev.cis_thirdparty_gold_layer.AllMetricValues`

        WHERE report_month = p_report_month
    );


    ASSERT duplicate_count = 0
    AS 'Duplicate vendor/metric records found';


    ASSERT vendor_count > 0
    AS 'No vendors found';


    ASSERT metric_count > 0
    AS 'No metrics found';

END;