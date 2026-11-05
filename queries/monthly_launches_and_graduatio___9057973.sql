-- part of a query repo
-- query name: Monthly launches and graduation rate
-- query link: https://dune.com/queries/9057973
-- Line chart: graduation_rate_pct (launches as bars in a separate chart; no dual axis).

SELECT month, launches, graduations, graduation_rate_pct FROM dune.mysticalhead.dataset_ps_monthly ORDER BY month
