-- part of a query repo
-- query name: Survivor trading positions by P&L
-- query link: https://dune.com/queries/9057969
-- Bar chart, log y-axis.

SELECT bucket, positions FROM dune.mysticalhead.dataset_ps_pnl_buckets ORDER BY step
