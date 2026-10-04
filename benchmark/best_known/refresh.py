#!/usr/bin/env python3
"""Refresh colbourn_tables.csv from the Colbourn covering-array tables. Stdlib only.

The snapshot index is github.com/ugroempi/CAs/blob/main/ColbournTables.md
(November 2024 status). It links one page per (t, v):

    https://www.data2intelligence.de/ColbournTables/t{t}v{v}.html

Each page lists rows (t, v, k, N, source): N rows are known to suffice for up
to k columns. The pages wrap the table in an outer <tr><td>, so this parser
keeps only rows of exactly five innermost cells; a regex over <tr>...</tr>
would lose each table's first row (plan, appendix "the best-known tables").

    python3 benchmark/best_known/refresh.py --check benchmark/best_known/colbourn_tables.csv
    python3 benchmark/best_known/refresh.py --out benchmark/best_known/colbourn_tables.csv

`--check` fetches and compares without writing. `--cache DIR` keeps the
fetched pages (and reads them from there on the next run) so a refresh can
be inspected or repeated offline.
"""
import argparse, csv, datetime, html.parser, pathlib, subprocess, sys, time, urllib.error, urllib.request

URL = 'https://www.data2intelligence.de/ColbournTables/t{t}v{v}.html'
STATUS = '2024-11'  # the tables' own status, from the snapshot index
# The pages the snapshot holds: strength 2 and 3 with 2-25 values, strength 4
# with 2-9, strengths 5 and 6 with 2-5. Extend here, then refresh.
PAGES = ([(2, v) for v in range(2, 26)] + [(3, v) for v in range(2, 26)] +
         [(4, v) for v in range(2, 10)] + [(t, v) for t in (5, 6) for v in range(2, 6)])
FIELDS = ['t', 'v', 'k', 'N', 'source', 'status', 'retrieved']


class Rows(html.parser.HTMLParser):
    """Collects every <tr> of exactly five innermost <td> cells."""
    def __init__(self):
        super().__init__()
        self.rows, self.open_rows, self.cells = [], [], []

    def handle_starttag(self, tag, attrs):
        if tag == 'tr': self.open_rows.append([])
        elif tag == 'td': self.cells.append([])

    def handle_endtag(self, tag):
        if tag == 'td' and self.cells:
            text = ''.join(self.cells.pop()).strip()
            if self.open_rows: self.open_rows[-1].append(text)
        elif tag == 'tr' and self.open_rows:
            row = self.open_rows.pop()
            if len(row) == 5: self.rows.append(row)

    def handle_data(self, data):
        if self.cells: self.cells[-1].append(data)


def parse(text, t, v):
    p = Rows(); p.feed(text); p.close()
    out = []
    for tt, vv, k, n, source in p.rows:
        if (int(tt), int(vv)) != (t, v):
            raise ValueError(f't{t}v{v}: row for t{tt}v{vv}')
        out.append(dict(t=t, v=v, k=int(k), N=int(n), source=source))
    if not out: raise ValueError(f't{t}v{v}: no rows')
    ks = [r['k'] for r in out]
    if ks != sorted(ks): raise ValueError(f't{t}v{v}: k not ascending')
    return out


def download(url):
    """The body at `url`. Falls back to curl where Python has no CA certificates."""
    request = urllib.request.Request(url, headers={'User-Agent': 'UnitTestDesign.jl benchmark refresh'})
    try:
        with urllib.request.urlopen(request, timeout=60) as response: return response.read()
    except urllib.error.URLError as e:
        if 'CERTIFICATE_VERIFY_FAILED' not in str(e): raise
        return subprocess.run(['curl', '-fsSL', '--max-time', '60', url], check=True, capture_output=True).stdout


def fetch(t, v, cache=None, delay=1.0):
    path = cache / f't{t}v{v}.html' if cache else None
    if path and path.exists(): return path.read_text()
    text = download(URL.format(t=t, v=v)).decode('utf-8')
    if path: path.write_text(text)
    time.sleep(delay)
    return text


def read(path):
    with open(path, newline='') as f:
        return list(csv.DictReader(f))


def key(r): return (int(r['t']), int(r['v']), int(r['k']), int(r['N']), r['source'])


def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument('--out', type=pathlib.Path, help='CSV to write')
    a.add_argument('--check', type=pathlib.Path, help='Existing CSV to compare against; writes nothing')
    a.add_argument('--cache', type=pathlib.Path, help='Directory for fetched pages')
    a.add_argument('--page', action='append', default=[], help='t:v, repeatable; default: the snapshot\'s pages')
    a.add_argument('--retrieved', default=datetime.date.today().isoformat())
    args = a.parse_args()
    if not (args.out or args.check): a.error('give --out or --check')
    pages = [tuple(map(int, p.split(':'))) for p in args.page] or PAGES
    if args.cache: args.cache.mkdir(parents=True, exist_ok=True)
    rows = []
    for t, v in pages:
        got = parse(fetch(t, v, args.cache), t, v)
        print(f't{t}v{v}: {len(got)} rows', file=sys.stderr)
        rows.extend(dict(r, status=STATUS, retrieved=args.retrieved) for r in got)
    if args.check:
        # Compare the pages the file holds; report fetched pages it lacks.
        held = {(int(r['t']), int(r['v'])) for r in read(args.check)}
        old = {key(r) for r in read(args.check) if (int(r['t']), int(r['v'])) in set(pages)}
        new = {key(r) for r in rows if (r['t'], r['v']) in held}
        for r in sorted(old - new): print('only in', args.check, r)
        for r in sorted(new - old): print('only on the pages', r)
        missing = sorted(set(pages) - held)
        if missing: print('pages the file lacks:', ' '.join(f't{t}v{v}' for t, v in missing))
        print(f'{len(old & new)} rows agree, {len(old - new)} only in the file, {len(new - old)} only on the pages')
        sys.exit(0 if old == new else 1)
    with open(args.out, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, lineterminator='\n')
        w.writeheader(); w.writerows(rows)
    print(f'{len(rows)} rows: {args.out}', file=sys.stderr)


if __name__ == '__main__': main()
