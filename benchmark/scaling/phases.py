#!/usr/bin/env python3
"""Summarize warm native phase events, excluding trial-wrapper recertification."""
import argparse, csv, json, pathlib, statistics, zipfile


def events_for(root, job):
    relative = job / pathlib.Path('events.jsonl')
    path = root / relative
    if path.exists():
        content = path.read_text()
    else:
        with zipfile.ZipFile(root / 'raw_jobs.zip') as archive:
            content = archive.read(str(relative)).decode()
    events = []
    for line in content.splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return events


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('results', type=pathlib.Path)
    parser.add_argument('--out', type=pathlib.Path, required=True)
    args = parser.parse_args()
    rows = []
    for result in json.loads(args.results.read_text())['results']:
        if result['status'] != 'ok':
            continue
        stage = None
        warm = []
        for event in events_for(args.results.parent, pathlib.Path(result['spec']['id'])):
            if event['event'] == 'stage':
                stage = event['name']
            elif event['event'] == 'phase' and stage == 'warm':
                warm.append(event)
        if len(warm) != result['spec']['runs']:
            continue
        row = dict(id=result['spec']['id'], solver=result['spec']['solver'],
                   family=result['spec']['family'], n=result['spec']['n'], v=result['spec']['v'])
        for key in ('classification_seconds', 'engine_seconds', 'validation_seconds',
                    'classification_bytes', 'engine_bytes', 'validation_bytes'):
            row[key] = statistics.median(event[key] for event in warm)
        # This sum of medians is a descriptive attribution total, not the
        # independently measured end-to-end median or a trial-adapter time.
        row['phase_seconds_sum'] = sum(row[key] for key in
            ('classification_seconds', 'engine_seconds', 'validation_seconds'))
        rows.append(row)
    if not rows:
        parser.error('no complete warm phase measurements found')
    with args.out.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)
    print(f'{len(rows)} rows: {args.out}')


if __name__ == '__main__':
    main()
