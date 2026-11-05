-- part of a query repo
-- query name: Once past $100k, survivors mostly stay there
-- query link: https://dune.com/queries/9057962
-- Bar chart.

SELECT CASE WHEN share_days_above_100k_pct < 25 THEN '1. under 25%' WHEN share_days_above_100k_pct < 50 THEN '2. 25–50%'
  WHEN share_days_above_100k_pct < 75 THEN '3. 50–75%' WHEN share_days_above_100k_pct < 90 THEN '4. 75–90%' WHEN share_days_above_100k_pct < 99 THEN '5. 90–99%' ELSE '6. 99–100%' END AS share_of_days_since_graduation_closed_at_100k,
  count(*) AS survivors FROM dune.mysticalhead.dataset_ps_survivors WHERE share_days_above_100k_pct IS NOT NULL GROUP BY 1 ORDER BY 1
