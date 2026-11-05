-- part of a query repo
-- query name: The 20 largest survivors
-- query link: https://dune.com/queries/9057967
-- Table.

SELECT rank, symbol, market_cap_usd, peak_mc_usd, mint FROM dune.mysticalhead.dataset_ps_top20 ORDER BY rank
