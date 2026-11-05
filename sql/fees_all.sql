-- Creator fees accrued per pump.fun token, all time (fees from 2025-05-13): SOL-quoted curve + WSOL-quoted PumpSwap pools.
WITH
sol AS (
  SELECT date_trunc('day', minute) AS d, avg(price) AS px FROM prices.usd
  WHERE blockchain = 'solana' AND contract_address = from_base58('So11111111111111111111111111111111111111112')
    AND minute >= TIMESTAMP '2025-05-12' GROUP BY 1
),
-- Bonding curve. Dune decodes trades before ~Nov 2025 in an older event format with no fee fields, so for those trades the
-- creator fee is estimated from volume at pump.fun's published curve rate: 0.05% until Sep 2, 2025, 0.30% after.
curve AS (
  SELECT mint, date_trunc('day', evt_block_time) AS d,
    sum(CASE WHEN creator_fee IS NOT NULL THEN cast(creator_fee AS double) / 1e9
             ELSE cast(coalesce(sol_amount, solAmount) AS double) / 1e9 * (CASE WHEN evt_block_date < DATE '2025-09-02' THEN 0.0005 ELSE 0.003 END) END) AS sol,
    sum(CASE WHEN creator_fee IS NULL
             THEN cast(coalesce(sol_amount, solAmount) AS double) / 1e9 * (CASE WHEN evt_block_date < DATE '2025-09-02' THEN 0.0005 ELSE 0.003 END) ELSE 0 END) AS est_sol
  FROM pumpdotfun_solana.pump_evt_tradeevent
  WHERE evt_block_date >= DATE '2025-05-13' AND coalesce(quote_mint, '11111111111111111111111111111111') = '11111111111111111111111111111111'
    
  GROUP BY 1, 2
),
pools AS (
  SELECT pool, base_mint AS mint FROM pumpdotfun_solana.pump_amm_evt_createpoolevent
  WHERE quote_mint = 'So11111111111111111111111111111111111111112' 
),
amm_raw AS (
  SELECT pool, date_trunc('day', evt_block_time) AS d, cast(coin_creator_fee AS double) AS f
  FROM pumpdotfun_solana.pump_amm_evt_buyevent WHERE evt_block_date >= DATE '2025-05-13'
  UNION ALL
  SELECT pool, date_trunc('day', evt_block_time), cast(coin_creator_fee AS double)
  FROM pumpdotfun_solana.pump_amm_evt_sellevent WHERE evt_block_date >= DATE '2025-05-13'
),
amm AS (SELECT p.mint, a.d, sum(a.f) / 1e9 AS sol FROM amm_raw a JOIN pools p ON p.pool = a.pool GROUP BY 1, 2),
x AS (
  SELECT c.mint, c.sol, c.sol * s.px AS usd, c.est_sol * s.px AS est_usd, 'curve' AS venue FROM curve c LEFT JOIN sol s ON s.d = c.d
  UNION ALL
  SELECT a.mint, a.sol, a.sol * s.px, 0e0, 'pumpswap' FROM amm a LEFT JOIN sol s ON s.d = a.d
),
per_mint AS (
  SELECT mint, sum(sol) AS sol, sum(usd) AS usd, sum(est_usd) AS est_usd, sum(CASE WHEN venue = 'curve' THEN usd ELSE 0 END) AS curve_usd
  FROM x GROUP BY 1
)

SELECT 'token' AS level, count(*) AS n, sum(usd) AS total_usd, sum(sol) AS total_sol, sum(curve_usd) AS curve_usd, sum(est_usd) AS est_usd,
  approx_percentile(usd, 0.5) AS p50, approx_percentile(usd, 0.9) AS p90, approx_percentile(usd, 0.99) AS p99, approx_percentile(usd, 0.999) AS p999,
  count_if(usd >= 1e2) AS n_100, count_if(usd >= 1e3) AS n_1k, count_if(usd >= 1e4) AS n_10k, count_if(usd >= 1e5) AS n_100k, count_if(usd >= 1e6) AS n_1m,
  max(usd) AS max_usd
FROM per_mint
UNION ALL
SELECT 'other_quote_trades', count(*), NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM pumpdotfun_solana.pump_evt_tradeevent WHERE evt_block_date >= DATE '2025-05-13' AND quote_mint IS NOT NULL AND quote_mint <> '11111111111111111111111111111111'
UNION ALL
SELECT 'curve_trades', count(*), NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM pumpdotfun_solana.pump_evt_tradeevent WHERE evt_block_date >= DATE '2025-05-13'
