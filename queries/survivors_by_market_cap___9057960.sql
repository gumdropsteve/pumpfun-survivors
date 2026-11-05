-- part of a query repo
-- query name: Survivors by market cap
-- query link: https://dune.com/queries/9057960
-- Bar chart.

SELECT CASE WHEN market_cap_usd < 2.5e5 THEN '1. $100k–250k' WHEN market_cap_usd < 5e5 THEN '2. $250k–500k'
  WHEN market_cap_usd < 1e6 THEN '3. $500k–1M' WHEN market_cap_usd < 1e7 THEN '4. $1M–10M' WHEN market_cap_usd < 1e8 THEN '5. $10M–100M' ELSE '6. $100M+' END AS band,
  count(*) AS survivors FROM dune.mysticalhead.dataset_ps_survivors GROUP BY 1 ORDER BY 1
