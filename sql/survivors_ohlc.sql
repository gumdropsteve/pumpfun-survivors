-- Lifetime history of the pump.fun survivor tokens from Dune trades (fixes GeckoTerminal's ~1-year history cap).
-- Daily VWAP x 1B supply = daily market cap (robust to single bad trades). Coverage starts 2024-05-30.
WITH s(mint, cur_px) AS (VALUES
    {{SURVIVORS}}  -- one row per survivor from data/survivors.csv
),
tr AS (
  SELECT s.mint, t.block_time, t.amount_usd AS usd, t.token_bought_amount AS tok, t.project FROM dex_solana.trades t JOIN s ON t.token_bought_mint_address = s.mint
  WHERE t.block_month >= DATE '2024-05-01' AND t.amount_usd > 0 AND t.token_bought_amount > 0
  UNION ALL
  SELECT s.mint, t.block_time, t.amount_usd, t.token_sold_amount, t.project FROM dex_solana.trades t JOIN s ON t.token_sold_mint_address = s.mint
  WHERE t.block_month >= DATE '2024-05-01' AND t.amount_usd > 0 AND t.token_sold_amount > 0
),
daily AS (
  SELECT mint, date_trunc('day', block_time) AS d,
    min_by(usd / tok, block_time) * 1e9 AS open_mc,
    max(usd / tok) * 1e9 AS high_mc,
    min(usd / tok) * 1e9 AS low_mc,
    max_by(usd / tok, block_time) * 1e9 AS close_mc,
    approx_percentile(usd / tok, 0.99) * 1e9 AS high_p99_mc,
    approx_percentile(usd / tok, 0.01) * 1e9 AS low_p01_mc,
    sum(usd) / sum(tok) * 1e9 AS vwap_mc,
    sum(usd) AS vol, count(*) AS n
  FROM tr WHERE usd >= 10 GROUP BY 1, 2
)
SELECT * FROM daily ORDER BY mint, d
