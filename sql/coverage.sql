SELECT project, min(block_date) first_day, count(DISTINCT CASE WHEN token_bought_mint_address LIKE '%pump' THEN token_bought_mint_address ELSE token_sold_mint_address END) mints
FROM dex_solana.trades
WHERE (token_bought_mint_address LIKE '%pump' OR token_sold_mint_address LIKE '%pump') AND project IN ('pumpdotfun','pumpswap','raydium')
GROUP BY 1
