-- part of a query repo
-- query name: Holders vs market cap
-- query link: https://dune.com/queries/9057965
-- Scatter, log x and y.

SELECT holders, market_cap_usd FROM dune.mysticalhead.dataset_ps_survivors WHERE holders >= 50
