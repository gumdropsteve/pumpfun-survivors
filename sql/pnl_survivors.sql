-- Trader P&L on the pump.fun survivor tokens (alive above $100k on Oct 31, 2026). Survivorship-biased by design.
-- Per (wallet, token), average-cost method on swaps (dex_solana.trades, from 2024-05-30):
--   realized   = sell proceeds - sold tokens x average buy cost
--   unrealized = tokens held now (solana_utils.latest_balances) x (Oct 31 price - average buy cost)
-- Transfer check: a wallet that only swapped holds exactly buys - sells. If its real balance differs by more than 5%
-- of what it swapped, tokens moved by plain transfer (in or out) and the position is excluded from the headline.
-- One pass over trades; outputs one row per token, one 'ALL' row, and 'BIN' rows (profit histogram for top-share maths).
WITH
s(mint, cur_px, ath_px) AS (VALUES
    {{SURVIVORS}}
),
tr AS (
  SELECT s.mint, t.trader_id AS w, t.block_time, t.token_bought_amount AS tok, t.amount_usd AS usd, 1 AS side
  FROM dex_solana.trades t JOIN s ON t.token_bought_mint_address = s.mint
  WHERE t.block_month >= DATE '2024-05-01' AND t.amount_usd > 0 AND t.token_bought_amount > 0
  UNION ALL
  SELECT s.mint, t.trader_id, t.block_time, t.token_sold_amount, t.amount_usd, -1
  FROM dex_solana.trades t JOIN s ON t.token_sold_mint_address = s.mint
  WHERE t.block_month >= DATE '2024-05-01' AND t.amount_usd > 0 AND t.token_sold_amount > 0
),
pos0 AS (
  SELECT mint, w,
    sum(CASE WHEN side = 1 THEN tok ELSE 0 END) AS b_tok, sum(CASE WHEN side = 1 THEN usd ELSE 0 END) AS b_usd,
    sum(CASE WHEN side = -1 THEN tok ELSE 0 END) AS s_tok, sum(CASE WHEN side = -1 THEN usd ELSE 0 END) AS s_usd,
    min(block_time) AS first_any,
    min(CASE WHEN side = 1 THEN block_time END) AS first_buy,
    min_by(usd / tok, CASE WHEN side = 1 THEN block_time END) AS first_buy_px
  FROM tr GROUP BY 1, 2
),
bal AS (
  SELECT token_mint_address AS mint, token_balance_owner AS w, sum(cast(token_balance AS double)) AS bal
  FROM solana_utils.latest_balances
  WHERE token_mint_address IN (SELECT mint FROM s) AND token_balance > 0
  GROUP BY 1, 2
),
pos AS (
  SELECT p.*, s.cur_px, s.ath_px, coalesce(b.bal, 0) AS bal,
    min(p.first_any) OVER (PARTITION BY p.mint) AS t0
  FROM pos0 p JOIN s ON s.mint = p.mint LEFT JOIN bal b ON b.mint = p.mint AND b.w = p.w
),
pnl AS (
  SELECT *,
    b_tok > 0 AS has_buy,
    abs(bal - (b_tok - s_tok)) <= 0.05 * greatest(b_tok, s_tok) AS reconciles,
    CASE WHEN b_tok > 0 THEN b_usd / b_tok END AS avg_cost
  FROM pos
),
p2 AS (
  SELECT *,
    has_buy AND reconciles AS clean,
    CASE WHEN has_buy THEN s_usd - least(s_tok, b_tok) * avg_cost ELSE 0 END AS realized,
    CASE WHEN has_buy THEN bal * (cur_px - avg_cost) ELSE 0 END AS unrealized,
    bal * cur_px AS held_usd,
    first_buy < t0 + INTERVAL '1' HOUR AS early,
    first_buy_px >= 0.8 * ath_px AS near_peak
  FROM pnl
),
p3 AS (
  SELECT *, realized + unrealized AS total,
    CASE WHEN clean AND realized + unrealized > 0 THEN cast(floor(log10(realized + unrealized) * 10) AS integer) END AS pbin
  FROM p2
)
SELECT
  CASE WHEN grouping(mint) = 0 THEN mint WHEN grouping(pbin) = 0 THEN 'BIN' ELSE 'ALL' END AS mint,
  pbin,
  count(*) AS n_positions,
  count_if(NOT has_buy) AS n_no_buys,
  count_if(has_buy AND NOT reconciles) AS n_mismatch,
  count_if(has_buy AND NOT reconciles AND bal > b_tok - s_tok) AS n_mismatch_more_than_swapped,
  count_if(clean) AS n_clean,
  count_if(clean AND s_tok > 0) AS n_sold,
  count_if(clean AND s_tok > 0 AND realized > 0) AS n_realized_profit,
  count_if(clean AND total > 0) AS n_total_profit,
  count_if(clean AND total > 0 AND realized <= 0) AS n_profit_only_unrealized,
  count_if(clean AND bal > 0) AS n_still_holding,
  approx_percentile(CASE WHEN clean THEN realized END, 0.5) AS med_realized,
  approx_percentile(CASE WHEN clean THEN total END, 0.5) AS med_total,
  approx_percentile(CASE WHEN clean THEN total END, 0.9) AS p90_total,
  approx_percentile(CASE WHEN clean THEN total END, 0.99) AS p99_total,
  approx_percentile(CASE WHEN clean THEN total END, 0.1) AS p10_total,
  approx_percentile(CASE WHEN clean THEN b_usd END, 0.5) AS med_bought_usd,
  sum(CASE WHEN clean AND realized > 0 THEN realized ELSE 0 END) AS sum_realized_gains,
  sum(CASE WHEN clean AND realized < 0 THEN realized ELSE 0 END) AS sum_realized_losses,
  sum(CASE WHEN clean THEN unrealized ELSE 0 END) AS sum_unrealized,
  sum(CASE WHEN clean THEN held_usd ELSE 0 END) AS sum_held_usd,
  sum(CASE WHEN clean AND total > 0 THEN total ELSE 0 END) AS sum_profit,
  sum(CASE WHEN clean AND total < 0 THEN total ELSE 0 END) AS sum_loss,
  sum(CASE WHEN clean THEN b_usd ELSE 0 END) AS sum_bought_usd,
  sum(CASE WHEN clean THEN s_usd ELSE 0 END) AS sum_sold_usd,
  count_if(clean AND total <= -1e4) AS n_lost_10k,
  count_if(clean AND total > -1e4 AND total <= -1e3) AS n_lost_1k_10k,
  count_if(clean AND total > -1e3 AND total <= 0) AS n_lost_0_1k,
  count_if(clean AND total > 0 AND total <= 1e3) AS n_won_0_1k,
  count_if(clean AND total > 1e3 AND total <= 1e4) AS n_won_1k_10k,
  count_if(clean AND total > 1e4 AND total <= 1e5) AS n_won_10k_100k,
  count_if(clean AND total > 1e5 AND total <= 1e6) AS n_won_100k_1m,
  count_if(clean AND total > 1e6) AS n_won_1m,
  count_if(clean AND early) AS n_early, count_if(clean AND early AND total > 0) AS n_early_profit,
  approx_percentile(CASE WHEN clean AND early THEN total END, 0.5) AS med_early_total,
  sum(CASE WHEN clean AND early THEN total ELSE 0 END) AS sum_early_total,
  count_if(clean AND near_peak) AS n_peak, count_if(clean AND near_peak AND total > 0) AS n_peak_profit,
  approx_percentile(CASE WHEN clean AND near_peak THEN total END, 0.5) AS med_peak_total,
  sum(CASE WHEN clean AND near_peak THEN total ELSE 0 END) AS sum_peak_total,
  count(DISTINCT CASE WHEN clean THEN w END) AS n_wallets_clean
FROM p3
GROUP BY GROUPING SETS ((mint), (), (pbin))
