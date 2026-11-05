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
sol AS (
  SELECT date_trunc('day', minute) AS d, avg(price) AS px FROM prices.usd
  WHERE blockchain = 'solana' AND contract_address = from_base58('So11111111111111111111111111111111111111112') AND minute >= TIMESTAMP '2024-05-01'
  GROUP BY 1
),
daily AS (
  SELECT mint, date_trunc('day', block_time) AS d, sum(usd) AS vol, sum(usd) / sum(tok) * 1e9 AS mc, count(*) AS n
  FROM tr GROUP BY 1, 2
),
grad AS (SELECT mint, min(block_time) AS grad_time FROM tr WHERE project <> 'pumpdotfun' GROUP BY 1)
SELECT d.mint,
  min(d.d) AS first_day, max(d.d) AS last_day, g.grad_time,
  count(*) AS days_traded, sum(d.vol) AS life_vol, sum(d.n) AS n_trades,
  count_if(d.vol >= 1e4) AS days_vol_10k, count_if(d.vol >= 1e5) AS days_vol_100k, count_if(d.vol >= 1e6) AS days_vol_1m,
  max(d.mc) AS ath_mc_vwap, max_by(d.d, d.mc) AS ath_day,
  count_if(d.mc >= 410 * sl.px) AS days_above_grad, count_if(d.mc >= 1e5) AS days_mc_100k, count_if(d.mc >= 1e6) AS days_mc_1m,
  count_if(d.mc >= 1e7) AS days_mc_10m
FROM daily d LEFT JOIN sol sl ON sl.d = d.d LEFT JOIN grad g ON g.mint = d.mint
GROUP BY d.mint, g.grad_time
