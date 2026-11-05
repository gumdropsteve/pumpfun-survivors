-- Survivor enrichment over trades of $10 or more only (collect/enrich_dune.py --part 10 fills in the mints): the rule the
-- Dune OHLC candles use, which leaves out most bot and MEV flow (sub-cent buys, same-second round trips). Kept apart from
-- enrich_trades.tmpl.sql because one query computing both exceeded Dune's resource cap on 2026-11-05.
WITH
s(mint) AS (VALUES
    {{MINTS}}
),
b AS (
  SELECT s.mint, t.trader_id AS w, t.block_time, t.amount_usd AS usd,
    CASE WHEN t.token_sold_mint_address = 'So11111111111111111111111111111111111111112' THEN t.token_sold_amount END AS sol_paid
  FROM dex_solana.trades t JOIN s ON t.token_bought_mint_address = s.mint
  WHERE t.block_month >= DATE '2024-05-01' AND t.amount_usd >= 10 AND t.token_bought_amount > 0
),
se AS (
  SELECT s.mint, t.trader_id AS w, max(t.block_time) AS last_sell
  FROM dex_solana.trades t JOIN s ON t.token_sold_mint_address = s.mint
  WHERE t.block_month >= DATE '2024-05-01' AND t.amount_usd >= 10 AND t.token_sold_amount > 0
  GROUP BY 1, 2
),
px AS (SELECT date_trunc('day', block_time) AS d, approx_percentile(usd / sol_paid, 0.5) AS sol_usd FROM b WHERE sol_paid > 0 GROUP BY 1),
b2 AS (SELECT b.*, coalesce(b.sol_paid, b.usd / px.sol_usd) AS sol FROM b LEFT JOIN px ON px.d = date_trunc('day', b.block_time)),
buys AS (
  SELECT mint, count(*) AS buys_10, approx_percentile(sol, 0.5) AS median_buy_sol_10,
    approx_percentile(usd, 0.5) AS median_buy_usd_10, count(DISTINCT w) AS unique_buyers_10
  FROM b2 GROUP BY 1
),
wb AS (SELECT mint, w, min(block_time) AS first_buy FROM b GROUP BY 1, 2),
hold AS (
  SELECT wb.mint,
    approx_percentile(date_diff('second', wb.first_buy, se.last_sell) / 86400e0, 0.5) FILTER (WHERE se.last_sell > wb.first_buy) AS median_hold_days_10,
    count_if(se.last_sell > wb.first_buy) AS buyers_who_sold_10
  FROM wb LEFT JOIN se ON se.mint = wb.mint AND se.w = wb.w GROUP BY 1
),
wc AS (SELECT w, count(DISTINCT mint) AS n FROM wb GROUP BY 1),
overlap AS (SELECT wb.mint, count_if(wc.n >= 2) AS buyers_in_other_survivors_10 FROM wb JOIN wc ON wc.w = wb.w GROUP BY 1)
SELECT s.mint, buys.buys_10, buys.median_buy_sol_10, buys.median_buy_usd_10, buys.unique_buyers_10,
  hold.median_hold_days_10, hold.buyers_who_sold_10, overlap.buyers_in_other_survivors_10
FROM s LEFT JOIN buys ON buys.mint = s.mint LEFT JOIN hold ON hold.mint = s.mint LEFT JOIN overlap ON overlap.mint = s.mint
ORDER BY s.mint
