-- part of a query repo
-- query name: Launchpad tokens at $100k+ (CoinGecko categories)
-- query link: https://dune.com/queries/9057975
-- Bar chart.

SELECT launchpad, tokens_100k, tokens_1m, tokens_10m, top_token FROM dune.mysticalhead.dataset_ps_launchpads ORDER BY tokens_100k DESC
