"""Enrich the survivor set: per-token facts beyond price and volume.

    SNAPSHOT=2026-11-01 .venv/bin/python collect/enrich.py

Reads reports/<snapshot>/survivors.json (the survivor set) and writes, under
data/<snapshot>/enrich/:

    dexscreener_<date>.json   raw DexScreener tokens/v1 pairs for every survivor
    records_dexscreener_<date>.json   one normalized record per survivor (fields below)

<date> is the day of collection, so the facts can be re-pulled and compared
over time against the same survivor set.

Sources in this pass, both free and keyless:
- DexScreener: socials, websites (with their labels), every pair's dex and
  quote token, the main pool.
- CoinGecko coins/list?include_platform (data/<snapshot>/list.json, already
  pulled): the coin id, and contract addresses on other chains (bridged).

Other passes: collect/enrich_x.py (X activity, followers, account age, Ansem
mentions). Still to come (see docs/enrichment.md): Dune (dev buy, trade sizes, holding
times, wallet overlap, creator-reward redirection), Helius (dev holdings),
and a Claude pass for language, category and narrative.
"""
import datetime, json, os, re, sys, time, urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'analysis'))
from paths import DATA, REPORT  # noqa: E402

TODAY = datetime.datetime.utcnow().strftime('%Y-%m-%d')
OUT = os.path.join(DATA, 'enrich')
UA = {'User-Agent': 'launch-statistics/1.0'}

# A website link's label or URL, to the fact it is evidence of. First match wins per link.
LINK_FACTS = [
    ('whitepaper', re.compile(r'white ?paper|litepaper', re.I)),
    ('tokenomics', re.compile(r'tokenomics', re.I)),
    ('docs', re.compile(r'\bdocs?\b|gitbook|documentation', re.I)),
    ('github', re.compile(r'github', re.I)),
    ('staking', re.compile(r'stak(e|ing)', re.I)),
    ('nft', re.compile(r'\bnfts?\b|exchange\.art|magiceden|tensor\.trade', re.I)),
    ('dev_lock', re.compile(r'lock|streamflow|vest', re.I)),
    ('app', re.compile(r'\bapp\b|dapp|\bsdk\b|\bapi\b', re.I)),
    ('burn', re.compile(r'\bburn', re.I)),
]
# Socials DexScreener lists as websites rather than socials.
SOCIAL_HOSTS = {
    'youtube': 'youtube.com', 'tiktok': 'tiktok.com', 'instagram': 'instagram.com', 'facebook': 'facebook.com',
    'reddit': 'reddit.com', 'linkedin': 'linkedin.com', 'medium': 'medium.com', 'twitch': 'twitch.tv',
    'threads': 'threads.net', 'linktree': 'linktr.ee', 'discord': 'discord.', 'telegram': 't.me/',
}


def get(url):
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
                return json.load(r)
        except Exception:
            if attempt == 3:
                raise
            time.sleep(2 * (attempt + 1))


def x_handle(url):
    m = re.match(r'https?://(?:www\.)?(?:x|twitter)\.com/(?:#!/)?([A-Za-z0-9_]{1,15})(?:[/?#]|$)', url or '')
    if not m or m.group(1).lower() in {'i', 'home', 'search', 'intent', 'share', 'hashtag'}:
        return None
    return m.group(1)


def normalize(mint, pairs, cg):
    pairs = sorted(pairs, key=lambda p: -((p.get('liquidity') or {}).get('usd') or 0))
    main = pairs[0] if pairs else {}
    info = next((p['info'] for p in pairs if p.get('info')), {})
    socials = info.get('socials') or []
    websites = info.get('websites') or []

    by_type = {}
    for s in socials:
        by_type.setdefault((s.get('type') or 'other').lower(), s.get('url'))
    for w in websites:
        url = (w.get('url') or '').lower()
        for kind, host in SOCIAL_HOSTS.items():
            if host in url:
                by_type.setdefault(kind, w.get('url'))
    x_url = by_type.get('twitter')
    handle = x_handle(x_url)
    # An X link to a community or a post rather than an account names no account.
    x_kind = 'account' if handle else ('community' if x_url and '/communities/' in x_url else ('other' if x_url else None))

    facts = set()
    for w in websites:
        text = f"{w.get('label') or ''} {w.get('url') or ''}"
        for fact, rx in LINK_FACTS:
            if rx.search(text):
                facts.add(fact)
                break
    site = next((w['url'] for w in websites if (w.get('label') or '').strip().lower() == 'website'), None) \
        or next((w['url'] for w in websites if not any(h in (w.get('url') or '').lower() for h in SOCIAL_HOSTS.values())), None)

    other_chains = sorted(k for k, v in (cg.get('platforms') or {}).items() if v and k != 'solana') if cg else []
    quotes = sorted({p['quoteToken']['symbol'] for p in pairs})
    created = main.get('pairCreatedAt')
    return {
        'mint': mint,
        'symbol': (main.get('baseToken') or {}).get('symbol'),
        'name': (main.get('baseToken') or {}).get('name'),
        'collected': TODAY,
        # Socials and web presence
        'website': site,
        'websites': [{'label': w.get('label'), 'url': w.get('url')} for w in websites],
        'x_url': x_url,
        'x_handle': handle,
        'x_kind': x_kind,
        'telegram': by_type.get('telegram'),
        'discord': by_type.get('discord'),
        'social_types': sorted(by_type),
        'other_socials': sorted(k for k in by_type if k not in {'twitter', 'telegram', 'discord'}),
        # Token design and origin
        'link_facts': sorted(facts),
        'has_whitepaper_link': 'whitepaper' in facts,
        'has_tokenomics_link': 'tokenomics' in facts,
        'has_docs_link': 'docs' in facts or 'whitepaper' in facts,
        'has_github_link': 'github' in facts,
        'has_nft_link': 'nft' in facts,
        'has_staking_link': 'staking' in facts,
        'has_dev_lock_link': 'dev_lock' in facts,
        'launched_on_pump': mint.endswith('pump'),
        'pairs': len(pairs),
        'quote_tokens': quotes,
        'paired_non_sol': [q for q in quotes if q not in ('SOL', 'WSOL')],
        'dexes': sorted({p['dexId'] for p in pairs}),
        'main_dex': main.get('dexId'),
        'main_pool': main.get('pairAddress'),
        'main_pool_created': datetime.datetime.utcfromtimestamp(created / 1000).strftime('%Y-%m-%d') if created else None,
        # Raydium as the main pool = graduated before PumpSwap (2025-03); PumpSwap = after.
        'graduated_to': {'pumpswap': 'pumpswap', 'raydium': 'raydium'}.get(main.get('dexId'), main.get('dexId')),
        'coingecko_id': cg.get('id') if cg else None,
        'other_chains': other_chains,
        'bridged': bool(other_chains),
        'sources': ['dexscreener'] + (['coingecko'] if cg else []),
    }


def main():
    survivors = list(json.load(open(os.path.join(REPORT, 'survivors.json'))))
    os.makedirs(OUT, exist_ok=True)
    pairs = []
    for i in range(0, len(survivors), 30):
        pairs += get('https://api.dexscreener.com/tokens/v1/solana/' + ','.join(survivors[i:i + 30]))
        time.sleep(0.4)  # 300 requests a minute is DexScreener's limit; 13 calls is nowhere near it.
    json.dump(pairs, open(os.path.join(OUT, f'dexscreener_{TODAY}.json'), 'w'))

    by_mint = {}
    for p in pairs:
        by_mint.setdefault(p['baseToken']['address'], []).append(p)
    cg = {}
    list_path = os.path.join(DATA, 'list.json')
    if os.path.exists(list_path):
        want = set(survivors)
        for c in json.load(open(list_path)):
            for v in (c.get('platforms') or {}).values():
                if v in want:
                    cg[v] = c
    records = [normalize(m, by_mint.get(m, []), cg.get(m)) for m in survivors]
    json.dump(records, open(os.path.join(OUT, f'records_dexscreener_{TODAY}.json'), 'w'), indent=1)

    n = len(records)
    def pct(k): return f"{sum(1 for r in records if r[k])} ({100 * sum(1 for r in records if r[k]) / n:.0f}%)"
    print(f'{n} survivors, {len(by_mint)} with pairs')
    for k in ('x_handle', 'website', 'telegram', 'discord', 'has_docs_link', 'has_github_link', 'has_nft_link', 'bridged', 'paired_non_sol'):
        print(f'  {k:18} {pct(k)}')
    print('wrote', os.path.relpath(OUT))


if __name__ == '__main__':
    main()
