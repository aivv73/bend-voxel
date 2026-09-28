"""Launch controlled worker/resource processes through the production supervisor."""
import json
import os
from pathlib import Path
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts'))
from megascene_supervisor import POLICY, supervise

case, destination, helper = sys.argv[1:]
destination = Path(destination); destination.mkdir()
identity = dict(campaign_id='fixture',series_id='fixture',attempt_id='fixture',synthetic=True)
(destination/'manifest.json').write_text(json.dumps({'schema':'megascene-evidence/1',**identity}))
env = {**os.environ,**{'MEGASCENE_'+k.upper():v for k,v in [('campaign','fixture'),('series','fixture'),('attempt','fixture')]},
       'MEGASCENE_EVENTS':str(destination/'cpu.jsonl')}
# Fault injection at the runner boundary only. Production constants are unchanged.
if case == 'startup': POLICY['startup_ns'] = 200_000_000
if case == 'watchdog': POLICY['watchdog_ns'] = 200_000_000
now = str(time.monotonic_ns())
probe = {'record_type':'heap_sample','status':'measured','device':'fixture','sample_begin_ns':now,'sample_end_ns':now,
         'scope':'synthetic_preflight','heaps':[{'heap':'0','usage_bytes':'0','budget_bytes':str(1024**3)}]}
worker = Path(__file__).with_name('supervisor_worker.py')
if case == 'persistence':
    # Real failing file descriptor at the supervisor's persistence boundary.
    original_open = Path.open
    def controlled_open(path, *args, **kwargs):
        if path.name == 'reference.jsonl':
            return open('/dev/full','wb',buffering=0)
        return original_open(path,*args,**kwargs)
    Path.open = controlled_open
result = supervise([sys.executable,str(worker),'worker',case,helper], destination, env, destination, identity,
                   dict(warmup='0',frames='1',deadline_s='1' if case == 'case' else '5'),
                   300_000_000 if case == 'campaign' else 10_000_000_000,
                   probe=probe,monitor_command=[sys.executable,str(worker),'monitor',case])
print(json.dumps(result))
