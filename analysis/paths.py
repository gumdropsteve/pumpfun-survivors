"""Where a snapshot's data and report live.

Each collection run is a dated snapshot: data/<YYYY-MM-DD>/ holds the raw pulls,
reports/<YYYY-MM-DD>/ holds metrics.json, charts and the rendered report.
Set SNAPSHOT=YYYY-MM-DD to pick one; the default is the newest folder in data/.
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_snaps = sorted(d for d in os.listdir(os.path.join(ROOT, 'data')) if d[:2] == '20')
SNAPSHOT = os.environ.get('SNAPSHOT') or _snaps[-1]
DATA = os.path.join(ROOT, 'data', SNAPSHOT)
REPORT = os.path.join(ROOT, 'reports', SNAPSHOT)
os.makedirs(os.path.join(REPORT, 'img'), exist_ok=True)
