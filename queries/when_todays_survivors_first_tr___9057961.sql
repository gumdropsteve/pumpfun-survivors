-- part of a query repo
-- query name: When today's survivors first traded
-- query link: https://dune.com/queries/9057961
-- Bar chart by month. Dune's trade data starts 2024-05-30, so the first bar includes older tokens.

SELECT CAST(first_trade_month || '-01' AS date) AS month, count(*) AS survivors FROM dune.mysticalhead.dataset_ps_survivors WHERE first_trade_month IS NOT NULL GROUP BY 1 ORDER BY 1
