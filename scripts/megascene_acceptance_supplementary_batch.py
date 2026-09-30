#!/usr/bin/env python3
"""Run the user-approved #68 supplementary matrix without changing timed work."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
from megascene_acceptance_primary_batch import retain_failure


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive', type=Path, required=True)
    p.add_argument('--work', type=Path, required=True)
    p.add_argument('--ledger', type=Path, required=True)
    p.add_argument('--execute', action='store_true')
    p.add_argument('--tag', default='first')
    p.add_argument('--only', nargs='*')
    p.add_argument('--repeat-history', action='store_true',
                   help='Run two further timed attempts per thread count from its validated source')
    args = p.parse_args()
    rows = [('history-small-1', ['--case','history','--threads','1']),
            ('history-small-6', ['--case','history','--threads','6']),
            ('history-small-12', ['--case','history','--threads','12']),
            ('history-small-360', ['--case','history','--threads','6','--resolution','640x360']),
            ('fill-history', ['--case','history','--threads','6','--diagnostic','fill']),
            ('body-rich-history', ['--case','history','--threads','6','--diagnostic','body-rich'])]
    for diagnostic in ('mixed-world','compact-reference'):
        for case in ('traversal','picking'):
            for profile in ('full','proxy'):
                rows.append((f'{diagnostic}-{case}-{profile}', ['--case',case,'--threads','6',
                    '--diagnostic',diagnostic,'--profile',profile]))
    if args.repeat_history:
        rows = [(f'history-small-{threads}-repeat-{repeat}',
                 ['--case','history','--threads',str(threads)])
                for threads in (1,6,12) for repeat in (2,3)]
    if args.only: rows = [row for row in rows if row[0] in args.only]
    if not args.execute:
        print(json.dumps(rows, indent=2)); return
    script = Path(__file__).resolve().parent
    result_path = args.archive/'checks'/'supplementary-batch.json'
    results = json.loads(result_path.read_text()) if result_path.exists() else []
    sources = {r['name']:r['archive'] for r in results}
    for name, options in rows:
        if name in sources: continue
        output = args.work/(name+'-'+args.tag)
        command = [sys.executable,str(script/'megascene.py'),'--preset','small','--seed','45',
            '--archive',str(args.archive),'--output',str(output),*options]
        validated = sources.get(name.split('-repeat-')[0]) if '-repeat-' in name else None
        if '-repeat-' in name and not validated:
            raise ValueError('A validated source for this thread count is required')
        source = sources.get('history-small-1') if name in ('history-small-6','history-small-12') else (
            sources.get(name.removesuffix('proxy')+'full') if name.endswith('-proxy') else None)
        if validated: command += ['--validated',validated]
        elif source: command += ['--runtime-from',source]
        wrapper = [sys.executable,str(script/'megascene_acceptance_run.py'),'--ledger',str(args.ledger),
            '--archive',str(args.archive/'checks'),'--name','supplementary-'+name+'-'+args.tag,'--timeout','1200','--',*command]
        print('START',name,flush=True)
        completed = subprocess.run(wrapper,check=False)
        if completed.returncode:
            print('FAILED',name,'retained',retain_failure(output,args.archive),flush=True)
            raise SystemExit(completed.returncode)
        manifest = json.loads((output/'manifest.json').read_text())
        archive = manifest['reproduction']['archive']
        summary = json.loads((Path(archive)/'summary.json').read_text())
        if any(summary[k]['status'] != 'pass' for k in ('schedule_completion','state_correctness','rendering_correctness','numeric_validity')):
            print('INCOMPLETE',name,archive,flush=True); raise SystemExit(2)
        results.append({'name':name,'archive':archive,'attempt_id':manifest['attempt_id']})
        result_path.write_text(json.dumps(results,indent=2)+'\n')
        sources[name]=archive
        print('END',name,archive,flush=True)

if __name__ == '__main__': main()
