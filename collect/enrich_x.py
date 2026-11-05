"""Enrich the survivor set from X: is the token's account alive, how big, how old,
and has Ansem (@blknoiz06) posted about it.

    SNAPSHOT=2026-11-01 .venv/bin/python collect/enrich_x.py [--date YYYY-MM-DD]

Needs X_BEARER_TOKEN in .env: an app-only token, read-only.

Reads data/<snapshot>/enrich/records_dexscreener_<date>.json (collect/enrich.py)
for each survivor's X handle, and reports/<snapshot>/survivors.json for its
first trade. Writes under data/<snapshot>/enrich/:

    x_users_<date>.json, x_last_posts_<date>.json, x_ansem_<date>.json   raw API answers
    records_x_<date>.json                                                one record per survivor

Calls: users and last posts in batches of 100 (about 8 requests), and one
full-archive search per survivor for Ansem's posts naming it (389, one a
second). His timeline endpoint stops at ~3,200 posts (2026-08-19 on
2026-11-05), too recent for most survivors, so search it is.
"""
import datetime, json, os, re, sys, time, urllib.error, urllib.parse, urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'analysis'))
from paths import DATA, REPORT, ROOT  # noqa: E402

ENRICH = os.path.join(DATA, 'enrich')
ANSEM = 'blknoiz06'
ACTIVE_DAYS = 30


def env(name):
    if os.environ.get(name):
        return os.environ[name]
    for line in open(os.path.join(ROOT, '.env')):
        k, _, v = line.strip().partition('=')
        if k == name:
            return v.strip().strip('"\'')
    sys.exit(f'{name} missing from .env')


TOKEN = env('X_BEARER_TOKEN')


def x(path, **params):
    url = f'https://api.x.com/2/{path}?' + urllib.parse.urlencode(params)
    for attempt in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={'Authorization': f'Bearer {TOKEN}'}), timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 4:
                reset = int(e.headers.get('x-rate-limit-reset') or time.time() + 60)
                time.sleep(max(5, min(900, reset - time.time() + 2)))
                continue
            raise


def iso_day(s):
    return s[:10] if s else None


TICKER = re.compile(r'^[A-Za-z][A-Za-z0-9_]{1,14}$')


def ansem_search(rec, since_day):
    """Ansem's posts naming this token since its first trade, from full-archive
    search: its mint (in the text or a link), its X account, or its $ticker.
    A ticker alone is the weakest, since tickers repeat across tokens. One
    request per token, at most 100 posts back."""
    mint, handle = rec['mint'], rec.get('x_handle')
    sym = (rec.get('symbol') or '').lstrip('$')
    terms = [f'"{mint}"', f'url:{mint}'] + ([f'@{handle}'] if handle else []) + ([f'${sym}'] if TICKER.match(sym) else [])
    params = {'query': f"from:{ANSEM} ({' OR '.join(terms)})", 'max_results': 100,
              'tweet.fields': 'created_at,entities', 'start_time': f'{since_day or "2024-01-01"}T00:00:00Z'}
    page = x('tweets/search/all', **params)
    time.sleep(1.05)  # full-archive search allows one request a second
    hits = []
    for p in page.get('data', []):
        text, ents = p.get('text') or '', p.get('entities') or {}
        urls = ' '.join(u.get('expanded_url') or '' for u in ents.get('urls', []))
        kinds = []
        if mint in text or mint in urls:
            kinds.append('mint')
        if handle and any((m.get('username') or '').lower() == handle.lower() for m in ents.get('mentions', [])):
            kinds.append('account')
        if TICKER.match(sym) and any((c.get('tag') or '').upper() == sym.upper() for c in ents.get('cashtags', [])):
            kinds.append('ticker')
        hits.append({'id': p['id'], 'at': p.get('created_at'), 'kinds': kinds or ['search']})
    return hits, page


def main():
    date = sys.argv[sys.argv.index('--date') + 1] if '--date' in sys.argv else None
    if not date:
        found = sorted(f[-15:-5] for f in os.listdir(ENRICH) if f.startswith('records_dexscreener_'))
        if not found:
            sys.exit('run collect/enrich.py first')
        date = found[-1]
    base = json.load(open(os.path.join(ENRICH, f'records_dexscreener_{date}.json')))
    survivors = json.load(open(os.path.join(REPORT, 'survivors.json')))

    handles = sorted({r['x_handle'] for r in base if r.get('x_handle')}, key=str.lower)
    users, errors = {}, {}
    for i in range(0, len(handles), 100):
        page = x('users/by', usernames=','.join(handles[i:i + 100]),
                 **{'user.fields': 'created_at,public_metrics,description,verified,verified_type,most_recent_tweet_id,protected,location,url'})
        for u in page.get('data', []):
            users[u['username'].lower()] = u
        for e in page.get('errors', []):
            errors[(e.get('value') or '').lower()] = e.get('detail') or e.get('title')
    json.dump({'users': users, 'errors': errors}, open(os.path.join(ENRICH, f'x_users_{date}.json'), 'w'))

    last_ids = [u['most_recent_tweet_id'] for u in users.values() if u.get('most_recent_tweet_id')]
    last = {}
    for i in range(0, len(last_ids), 100):
        page = x('tweets', ids=','.join(last_ids[i:i + 100]), **{'tweet.fields': 'created_at'})
        for t in page.get('data', []):
            last[t['id']] = t['created_at']
    json.dump(last, open(os.path.join(ENRICH, f'x_last_posts_{date}.json'), 'w'))

    ansem_raw = {}

    collected = datetime.datetime.strptime(date, '%Y-%m-%d')
    records = []
    for r in base:
        h = (r.get('x_handle') or '').lower()
        u = users.get(h) if h else None
        first = survivors.get(r['mint'], {}).get('first')
        first_day = datetime.datetime.utcfromtimestamp(first).strftime('%Y-%m-%d') if first else None
        last_at = last.get(u.get('most_recent_tweet_id')) if u else None
        m = (u or {}).get('public_metrics') or {}
        hits, ansem_raw[r['mint']] = ansem_search(r, first_day)
        records.append({
            'mint': r['mint'],
            'symbol': r.get('symbol'),
            'collected': date,
            'x_handle': r.get('x_handle'),
            'x_found': bool(u),
            'x_error': errors.get(h) if h and not u else None,
            'x_followers': m.get('followers_count'),
            'x_following': m.get('following_count'),
            'x_posts': m.get('tweet_count'),
            'x_created': iso_day(u.get('created_at')) if u else None,
            'x_verified_type': u.get('verified_type') if u else None,
            'x_protected': u.get('protected') if u else None,
            'x_bio': (u.get('description') or None) if u else None,
            'x_last_post': iso_day(last_at),
            'x_active_30d': bool(last_at) and (collected - datetime.datetime.strptime(last_at[:10], '%Y-%m-%d')).days <= ACTIVE_DAYS,
            'first_trade': first_day,
            # Created before the token's first trade: an account that existed before the coin, not made for it.
            'x_predates_token': (u['created_at'][:10] < first_day) if u and first_day else None,
            # Days from the account's creation to the token's first trade; positive = the account came first.
            'x_account_lead_days': (datetime.datetime.strptime(first_day, '%Y-%m-%d') - datetime.datetime.strptime(u['created_at'][:10], '%Y-%m-%d')).days if u and first_day else None,
            # An account made at least 30 days before the token, not set up for its launch.
            'x_predates_token_30d': ((datetime.datetime.strptime(first_day, '%Y-%m-%d') - datetime.datetime.strptime(u['created_at'][:10], '%Y-%m-%d')).days >= 30) if u and first_day else None,
            'ansem_mentions': len(hits),
            'ansem_strong_mentions': sum(1 for hit in hits if 'mint' in hit['kinds'] or 'account' in hit['kinds']),
            'ansem_first': min((hit['at'] for hit in hits), default=None),
            'ansem_hits': hits[:20],
            'sources': ['x'],
        })
    json.dump(ansem_raw, open(os.path.join(ENRICH, f'x_ansem_{date}.json'), 'w'))
    json.dump(records, open(os.path.join(ENRICH, f'records_x_{date}.json'), 'w'), indent=1)

    n = len(records)
    found = [r for r in records if r['x_found']]
    print(f'{len(handles)} handles, {len(users)} found, {len(errors)} not ({len(set(errors.values()))} kinds of error)')
    print(f"active in the last {ACTIVE_DAYS} days: {sum(r['x_active_30d'] for r in records)} of {n}")
    print(f"account predates the token: {sum(1 for r in records if r['x_predates_token'])} of {len(found)} found")
    fol = sorted(r['x_followers'] for r in found if r['x_followers'] is not None)
    if fol:
        print(f'followers: median {fol[len(fol) // 2]:,}, p90 {fol[int(len(fol) * .9)]:,}, max {fol[-1]:,}; '
              f'>=1k {sum(f >= 1000 for f in fol)}, >=10k {sum(f >= 10000 for f in fol)}, >=100k {sum(f >= 100000 for f in fol)}')
    print(f"Ansem: tokens named {sum(1 for r in records if r['ansem_mentions'])} of {n}"
          f" (by mint or account {sum(1 for r in records if r['ansem_strong_mentions'])}); posts {sum(r['ansem_mentions'] for r in records)}")


if __name__ == '__main__':
    main()
