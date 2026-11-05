# The 0.0016%: what survives pump.fun

Of 24.6M tokens launched on pump.fun, **390 were alive above $100k** on October 31, 2026, about 1 in 62,984. This repo has the research on those survivors: the report, the per-token data, and the queries and scripts behind them.

- **Report:** [`report/full.pdf`](report/full.pdf) (full) · [`report/summary.pdf`](report/summary.pdf) (one page)
- **Dune dashboard:** https://dune.com/mysticalhead/the-0-0016-what-survives-pump-fun
- **Per-token data:** [`data/survivors.csv`](data/survivors.csv) and [`data/survivor_enrichment.csv`](data/survivor_enrichment.csv)

## Findings

- **390 survivors out of 24.6M launches (0.0016%).** 118 are above $1M, 17 above $10M, and one (Fartcoin) above $100M. The median survivor is $402k.
- **The typical token never gets going.** Across the 19.2M pump.fun tokens Dune can see, the median lifetime volume is $1k, and the median token trades on 1 day.
- **Graduation is about 1 in 116** in a normal stretch (0.86%). July's BOOST incentive change pushed it to 2.95%.
- **Once past $100k, survivors stay there.** The median survivor closed at $100k or more on 99% of its days since graduating.
- **Even in the winners, 59% of trading positions are under water.** The top 1% of positions hold 82% of all profit.

What the survivors are, from section 11 of the report (collected November 5, 2026):

- **Web presence:** 90% list an X account and 90% a website. Only 4% link to GitHub, and 4% are also on another chain.
- **X activity:** 72% posted on X in the last 30 days. The median account has about 3,000 followers.
- **Ansem:** he posted about 16 survivors by mint or by X account.
- **Devs at launch:** 93% of devs bought at launch, with a median of 1.5 SOL (5.1% of supply). 51% still hold some, and 80 hold over 1% of supply.
- **Creator rewards:** for 39 survivors they now go to a different wallet than the creator's, and for 92 they go to no one. 116 use pump.fun fee sharing.
- **Category:** by their own materials, 188 are memes, 130 projects and 50 memes with utility. 165 ship software, and 9 publicly name their dev.
- **Hackathon:** 38 survivors entered pump.fun's Build in Public hackathon, and 8 of its 12 winners are survivors.

## What's here

| Path | What |
|---|---|
| `report/` | The report: full and one-page versions, as PDF and HTML. Section 12 has the methodology and sources, and every row of section 11 names its source. |
| `data/survivors.csv` | One row per survivor: market cap, liquidity, holders, top-10 share, age, peak, lifetime volume, days above $100k, creator fees. |
| `data/survivor_enrichment.csv` | One row per survivor: socials, links, pairs, X account stats, Ansem mentions, dev buy and holdings, creator-reward status, buy sizes and hold times, a classification (category, narratives, language, software, tokenomics, doxxed dev, with quoted evidence), and the hackathon result with its source posts. List fields are `|`-separated. |
| `sql/` | The Dune queries. `{{SURVIVORS}}` / `{{MINTS}}` stand for the survivor rows from `data/survivors.csv`. |
| `collect/` | The enrichment collectors: DexScreener and CoinGecko (`enrich.py`), X API (`enrich_x.py`), Claude classification (`enrich_classify.py`). |

The per-token files list 388 survivors. One survivor is left out of them at the publisher's request; it is counted in every total.

## Sources

- **Dune:** `dex_solana.trades` from 2024-05-30, pump.fun decoded events (`pumpdotfun_solana`), `solana_utils.latest_balances`, and the [adam_tehc/pumpfun](https://dune.com/adam_tehc/pumpfun) dashboard.
- **Market and token APIs:** [DexScreener](https://docs.dexscreener.com/api/reference), [GeckoTerminal](https://www.geckoterminal.com/), [CoinGecko](https://docs.coingecko.com/reference/coins-list), [DefiLlama](https://defillama.com/protocol/pump).
- **X API v2:** user lookup, plus full-archive search for Ansem's posts and hackathon posts.
- **Claude** (`claude-opus-5-5`): reads each token's own website, X bio and links. These are the promoters' own claims, reported as given, not verified.
- **Hackathon sources:** [Proof of Potato](https://www.proofofpotato.com/hackathon), and @pumpspotlight's winner announcements on X.
- **Third-party research:** cited in the report, section 10.

Snapshots: survivors as of October 31, 2026; enrichment collected November 5, 2026.
