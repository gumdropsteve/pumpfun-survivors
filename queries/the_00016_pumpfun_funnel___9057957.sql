-- part of a query repo
-- query name: The 0.0016%: pump.fun funnel
-- query link: https://dune.com/queries/9057957
-- Bar chart, log y-axis.

SELECT stage, tokens FROM dune.mysticalhead.dataset_ps_funnel ORDER BY step
