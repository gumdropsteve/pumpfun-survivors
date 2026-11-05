-- Survivor enrichment: trading behaviour and the dev, one row per survivor (collect/enrich_dune.py fills in the mints).
-- Trades: dex_solana.trades from 2024-05-30, every venue, both sides. A buy's size in SOL is what it paid when it paid
-- in SOL; otherwise its USD over that day's SOL price, read from this token set's own SOL-paid trades.
-- Hold time: a wallet's first buy to its last sell, for wallets that bought and later sold; still-holding is the rest.
-- Overlap: buyers of this survivor who also bought at least one other survivor.
-- Dev: the create event's signer. Initial buy = the dev's bonding-curve buys within 60s of creation.
-- Creator now: the latest creator pump.fun records for the token (trade events, PumpSwap pool, set-creator events);
-- "redirected" when it is not the wallet that created it. Fee sharing: a trade event carrying shareholders.
WITH
s(mint) AS (VALUES
    {{MINTS}}
),
b AS (
  SELECT s.mint, t.trader_id AS w, t.block_time, t.amount_usd AS usd,
    CASE WHEN t.token_sold_mint_address = 'So11111111111111111111111111111111111111112' THEN t.token_sold_amount END AS sol_paid
  FROM dex_solana.trades t JOIN s ON t.token_bought_mint_address = s.mint
  WHERE t.block_month >= DATE '2024-05-01' AND t.amount_usd > 0 AND t.token_bought_amount > 0
),
se AS (
  SELECT s.mint, t.trader_id AS w, t.block_time
  FROM dex_solana.trades t JOIN s ON t.token_sold_mint_address = s.mint
  WHERE t.block_month >= DATE '2024-05-01' AND t.amount_usd > 0 AND t.token_sold_amount > 0
),
px AS (
  SELECT date_trunc('day', block_time) AS d, approx_percentile(usd / sol_paid, 0.5) AS sol_usd
  FROM b WHERE sol_paid > 0 GROUP BY 1
),
b2 AS (
  SELECT b.*, coalesce(b.sol_paid, b.usd / px.sol_usd) AS sol
  FROM b LEFT JOIN px ON px.d = date_trunc('day', b.block_time)
),
buys AS (
  SELECT mint,
    count(*) AS buys,
    count_if(sol > 100) AS buys_over_100_sol,
    count_if(sol > 1) AS buys_over_1_sol,
    count_if(usd > 10000) AS buys_over_10k_usd,
    count_if(usd > 100) AS buys_over_100_usd,
    approx_percentile(sol, 0.5) AS median_buy_sol,
    approx_percentile(usd, 0.5) AS median_buy_usd,
    count(DISTINCT w) AS unique_buyers
  FROM b2 GROUP BY 1
),
wb AS (SELECT mint, w, min(block_time) AS first_buy FROM b GROUP BY 1, 2),
ws AS (SELECT mint, w, max(block_time) AS last_sell FROM se GROUP BY 1, 2),
hold AS (
  SELECT wb.mint,
    approx_percentile(date_diff('second', wb.first_buy, ws.last_sell) / 86400e0, 0.5)
      FILTER (WHERE ws.last_sell > wb.first_buy) AS median_hold_days,
    count_if(ws.last_sell > wb.first_buy) AS buyers_who_sold,
    count_if(ws.last_sell IS NULL) AS buyers_never_sold
  FROM wb LEFT JOIN ws ON ws.mint = wb.mint AND ws.w = wb.w
  GROUP BY 1
),
wc AS (SELECT w, count(DISTINCT mint) AS n FROM wb GROUP BY 1),
overlap AS (
  SELECT wb.mint,
    count_if(wc.n >= 2) AS buyers_in_other_survivors,
    avg(wc.n - 1) AS avg_other_survivors_per_buyer
  FROM wb JOIN wc ON wc.w = wb.w GROUP BY 1
),
cr AS (
  SELECT c.mint, cast(c.user AS varchar) AS dev, c.evt_block_time AS created, c.evt_tx_id AS create_tx
  FROM pumpdotfun_solana.pump_evt_createevent c JOIN s ON c.mint = s.mint
),
te AS (
  SELECT t.mint, cast(t.user AS varchar) AS u, t.evt_block_time, t.evt_tx_id,
    coalesce(t.is_buy, t.isBuy) AS is_buy,
    cast(coalesce(t.sol_amount, t.solAmount) AS double) / 1e9 AS sol,
    cast(coalesce(t.token_amount, t.tokenAmount) AS double) / 1e6 AS tok,
    cast(t.creator AS varchar) AS creator, t.shareholders IS NOT NULL AS shared
  FROM pumpdotfun_solana.pump_evt_tradeevent t JOIN s ON t.mint = s.mint
  WHERE t.evt_block_date >= DATE '2024-01-01'
),
devbuy AS (
  SELECT cr.mint,
    sum(te.sol) FILTER (WHERE te.is_buy) AS dev_initial_buy_sol,
    sum(te.tok) FILTER (WHERE te.is_buy) AS dev_initial_buy_tokens,
    bool_or(te.evt_tx_id = cr.create_tx AND te.is_buy) AS dev_bought_in_create_tx
  FROM cr LEFT JOIN te ON te.mint = cr.mint AND te.u = cr.dev AND te.evt_block_time <= cr.created + INTERVAL '60' SECOND
  GROUP BY 1
),
creators AS (
  SELECT mint, creator, evt_block_time FROM te WHERE creator IS NOT NULL
  UNION ALL
  SELECT p.base_mint, cast(p.coin_creator AS varchar), p.evt_block_time
  FROM pumpdotfun_solana.pump_amm_evt_createpoolevent p JOIN s ON p.base_mint = s.mint WHERE p.coin_creator IS NOT NULL
  UNION ALL
  SELECT e.base_mint, cast(e.coin_creator AS varchar), e.evt_block_time
  FROM pumpdotfun_solana.pump_amm_evt_setbondingcurvecoincreatorevent e JOIN s ON e.base_mint = s.mint
  UNION ALL
  SELECT e.mint, cast(e.creator AS varchar), e.evt_block_time
  FROM pumpdotfun_solana.pump_evt_setcreatorevent e JOIN s ON e.mint = s.mint
),
cnow AS (
  SELECT mint, max_by(creator, evt_block_time) AS creator_now, count(DISTINCT creator) AS creators_seen
  FROM creators GROUP BY 1
),
shared AS (SELECT mint, bool_or(shared) AS fee_sharing FROM te GROUP BY 1),
devbal AS (
  SELECT cr.mint, sum(cast(l.token_balance AS double)) AS dev_tokens_now
  FROM cr JOIN solana_utils.latest_balances l ON l.token_mint_address = cr.mint AND l.token_balance_owner = cr.dev
  GROUP BY 1
)
SELECT s.mint,
  buys.buys, buys.buys_over_100_sol, buys.buys_over_1_sol, buys.buys_over_10k_usd, buys.buys_over_100_usd,
  buys.median_buy_sol, buys.median_buy_usd, buys.unique_buyers,
  hold.median_hold_days, hold.buyers_who_sold, hold.buyers_never_sold,
  overlap.buyers_in_other_survivors, overlap.avg_other_survivors_per_buyer,
  cr.dev, cast(cr.created AS varchar) AS created,
  devbuy.dev_initial_buy_sol, devbuy.dev_initial_buy_tokens, devbuy.dev_bought_in_create_tx,
  coalesce(devbal.dev_tokens_now, 0) AS dev_tokens_now,
  cnow.creator_now, cnow.creators_seen,
  cnow.creator_now IS NOT NULL AND cr.dev IS NOT NULL AND cnow.creator_now <> cr.dev AS creator_redirected,
  shared.fee_sharing
FROM s
LEFT JOIN buys ON buys.mint = s.mint
LEFT JOIN hold ON hold.mint = s.mint
LEFT JOIN overlap ON overlap.mint = s.mint
LEFT JOIN cr ON cr.mint = s.mint
LEFT JOIN devbuy ON devbuy.mint = s.mint
LEFT JOIN devbal ON devbal.mint = s.mint
LEFT JOIN cnow ON cnow.mint = s.mint
LEFT JOIN shared ON shared.mint = s.mint
ORDER BY s.mint
