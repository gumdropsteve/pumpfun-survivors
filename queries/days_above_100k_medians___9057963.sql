-- part of a query repo
-- query name: Days above $100k: medians
-- query link: https://dune.com/queries/9057963
-- Counters (exact medians; 389 survivors with history).

WITH s AS (SELECT * FROM dune.mysticalhead.dataset_ps_survivors WHERE days_since_graduation IS NOT NULL),
  med AS (SELECT array_sort(array_agg(days_closed_above_100k)) AS a, array_sort(array_agg(days_since_graduation)) AS b, array_sort(array_agg(share_days_above_100k_pct)) AS c, count(*) AS n FROM s)
SELECT element_at(a, CAST((n + 1) / 2 AS integer)) AS median_days_closed_above_100k, element_at(b, CAST((n + 1) / 2 AS integer)) AS median_days_since_graduation,
  element_at(c, CAST((n + 1) / 2 AS integer)) AS median_share_pct, (SELECT count_if(share_days_above_100k_pct >= 90) FROM s) AS survivors_90pct_plus, n AS survivors FROM med
