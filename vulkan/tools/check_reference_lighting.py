#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT/'build/milestone-6-reference'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify-existing', action='store_true')
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    commands = []

    def run(command, name):
        result = subprocess.run(list(map(str, command)), cwd=ROOT, text=True, capture_output=True, timeout=600)
        (BUILD/name).write_text(result.stdout)
        (BUILD/(name+'.stderr')).write_text(result.stderr)
        commands.append(dict(command=list(map(str, command)), status=result.returncode, log=name))
        (BUILD/('verify-existing-commands.json' if args.verify_existing else 'commands.json')).write_text(json.dumps(commands, indent=2)+'\n')
        assert result.returncode == 0 and 'SOME PROOFS FAIL' not in result.stdout+result.stderr, name
        return result.stdout

    if not args.verify_existing:
        for source, name, output in [('reference_resolution','resolution-probe','resolution-runtime.log'),
                                     ('reference_matrix','matrix-dump','matrix-palette.jsonl'),
                                     ('reference_lighting','evidence','receivers.jsonl')]:
            run(['bend', f'tests/{source}.bend', '-o', BUILD/name], name+'-compile.log')
            run([BUILD/name, '+RTS', '--threads', '4', '-RTS'], output)
    assert (BUILD/'resolution-runtime.log').read_text().strip() == 'base_width=128 effective_atelier_width=512'
    run([sys.executable, 'tools/reference_lighting.py'], 'verification.log')
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'..').glob('*.bend')}
    (BUILD/'dependency-sha256.json').write_text(json.dumps(hashes, indent=2)+'\n')
    print('Original Body/Surface cached512/direct512, explicit128 experiment, 2226 receivers and exact 16-cell cut/repeat/reset passed')


if __name__ == '__main__':
    main()
