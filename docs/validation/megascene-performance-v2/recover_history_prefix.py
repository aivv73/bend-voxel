import argparse
import copy
import hashlib
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3]/'scripts'))
from megascene import snapshot
from megascene_calibration_series import _values, matrix, scope
from megascene_inventory import read_json, require

p=argparse.ArgumentParser(description='Retain the two clean history controls and replace the excluded third control.')
p.add_argument('--source',required=True)
p.add_argument('--series',required=True)
p.add_argument('--work',required=True)
args=p.parse_args()
source=Path(args.source).resolve()
target=Path(args.series).resolve()
work=Path(args.work).resolve()
old=read_json(source.read_text())
require(old['protocol']=='performance-v2' and old['scope']==scope(matrix('performance-v2')[1]), 'history scope required')
require(len(old['controls'])==3 and old['controls'][2].get('measurement_exclusion'), 'exact excluded history prefix required')
require(not target.exists() and not work.exists(), 'new correction paths required')
for run in old['validations'].values():
    validation=read_json((Path(run['archive'])/'validation.json').read_text())
    require(validation['status']=='pass' and validation['checked_frames']=='21721', 'complete retained validation required')
for index,run in enumerate(old['controls'][:2]):
    require(run['returncode']==0 and not run.get('binding_error') and not run.get('measurement_exclusion'), 'clean prefix required')
    require(_values(Path(run['archive']),old['scope'],('off','on')[index])['sufficient'], 'qualified duration required')
new=copy.deepcopy(old)
new.update(controls=new['controls'][:2],runs=[run for run in new['runs'] if not run.get('measurement_exclusion')],
           work_root=str(work),status='incomplete',
           continuation_from={'series':str(source),'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                              'retained_clean_controls':2,'retained_complete_validations':2},
           excluded_attempts=[copy.deepcopy(old['controls'][2])])
require(len(new['runs'])==4, 'only complete validations and clean prefix may continue')
target.parent.mkdir(parents=True,exist_ok=True)
snapshot(target,new)
print(target)
