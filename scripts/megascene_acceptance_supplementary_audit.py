#!/usr/bin/env python3
"""Bind new supplementary validations to retained primary schedules/captures."""
import argparse
import json
from pathlib import Path

KEYS = ('case','preset','seed','threads','resolution','profile','diagnostic','control','schedule')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--original-index',type=Path,required=True)
    p.add_argument('--batch',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args = p.parse_args()
    original = json.loads(args.original_index.read_text())
    eligible = {i for row in original['coverage'] for i in row['complete_runtime_attempts']}
    results = []
    for item in json.loads(args.batch.read_text()):
        root = Path(item['archive'])
        manifest = json.loads((root/'manifest.json').read_text())
        config = manifest['effective']
        frozen = json.loads((root/'schedule.json').read_text())
        review = json.loads((root/'review.json').read_text())
        primaries = [v for v in review['views'] if 'supplementary_to' not in v]
        candidates = []
        for old in original['attempts']:
            if old['attempt_id'] not in eligible or any(config.get(k) != old['configuration'].get(k) for k in KEYS): continue
            source = Path(old['archive'])
            if not (source/'assessments.json').exists(): continue
            old_frozen = json.loads((source/'schedule.json').read_text())
            before = {k:v for k,v in old_frozen.items() if k != 'supplementary_views'}
            after = {k:v for k,v in frozen.items() if k != 'supplementary_views'}
            if before != after: continue
            old_review = json.loads((source/'review.json').read_text())
            views = {v['name']:v for v in old_review['views']}
            matches = [v['name'] for v in primaries if v['name'] in views and v['capture']==views[v['name']]['capture']]
            candidates.append((len(matches),source,matches))
        if not candidates: raise ValueError('No unchanged accepted primary schedule for '+item['name'])
        count, source, matches = max(candidates,key=lambda x:x[0])
        validation = json.loads((root/'validation.json').read_text())
        detail = json.loads((root/'validation/comparison.json').read_text())['supplementary_validation']
        timed = json.loads((root/'comparison.json').read_text())['supplementary_validation']
        if validation['status'] != 'pass' or detail['status'] != 'pass' or timed['status'] != 'pass':
            raise ValueError('Supplementary restoration/validation failed')
        results.append(dict(item, original_archive=str(source), primary_schedule_unchanged=True,
            primary_capture_count=len(primaries), byte_identical_primary_captures=count,
            matching_primary_views=matches, supplementary_views=len(frozen['supplementary_views']),
            validation_restoration=detail, timed_exclusion=timed,
            assessment_reuse='permitted for matching captures only; added views require inspection'))
    args.output.write_text(json.dumps({'schema':'megascene-supplementary-preservation/1','rows':results},indent=2)+'\n')
    print(args.output)

if __name__ == '__main__': main()
