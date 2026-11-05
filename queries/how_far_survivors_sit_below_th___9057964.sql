-- part of a query repo
-- query name: How far survivors sit below their peak
-- query link: https://dune.com/queries/9057964
-- Bar chart.

SELECT CASE WHEN below_peak_pct < 25 THEN '1. under 25%' WHEN below_peak_pct < 50 THEN '2. 25–50%' WHEN below_peak_pct < 75 THEN '3. 50–75%'
  WHEN below_peak_pct < 90 THEN '4. 75–90%' ELSE '5. 90%+' END AS below_peak, count(*) AS survivors FROM dune.mysticalhead.dataset_ps_survivors WHERE below_peak_pct IS NOT NULL GROUP BY 1 ORDER BY 1
