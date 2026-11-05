-- part of a query repo
-- query name: In profit, by when the wallet got in
-- query link: https://dune.com/queries/9057970
-- Horizontal bar.

SELECT entry, in_profit_pct, positions FROM dune.mysticalhead.dataset_ps_pnl_entry
