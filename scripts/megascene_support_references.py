"""Actual Bend support transitions compared with small independent cell fixtures."""
from megascene_recipe import generate, bend_program
from megascene_inventory import read_json, require, digest
from megascene_checkpoints import initial_payload, mismatch
from megascene_support import Reference, schedule, CUT_FRAMES
from megascene_edit_references import bodies

CONFIG=dict(preset='small',seed='45',side_m='64',warmup='120',frames='3600',resolution='1920x1080')


def fixture_config(config):
    # The original three-span fixture is deliberately fixed at small/seed 45,
    # including for other baseline presets and source-transform controls.
    # Only the shortened schedules change its executable cut prefix.
    return config if config and config.get('schedule') in ('support-1-span-v1','support-2-span-v1') else CONFIG


def program(config=None):
    owners=generate('small',45)[2:5]
    source=bend_program(owners,2048).split('def main()',1)[0].replace('./src/','./')
    source=source.replace('import Base','import Base\nimport ./megascene_edit.bend as E')
    source+='''
def apply(due: Bool, +w: W.World, +point: R.Vec) -> IO(W.World):
  match due:
    case False{}: IO.pure(W.World,w)
    case True{}:
      do IO<W.World>:
        E.guard(w,point)
        return W.carve(w,point)

def loop(n: Nat, +frame: U32, +world: W.World) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      do IO<Unit>:
        +w : W.World = W.step(world,(1.0 / 60.0 : F32))
'''
    frozen=schedule(fixture_config(config))
    from megascene_edit_references import real
    from megascene_picking import value
    for a in frozen['actions']:
        source+=f"        +w : W.World <- apply(U32.is_eq(frame,{a['frame']}),w,R.Vec{{{','.join(real(value(x)) for x in a['target_m'])}}})\n"
    source+='''        M.emit(w)
        loop(rest,(frame + 1 : U32),w)

def main() -> IO(Unit):
  do IO<Unit>:
    +w : W.World = W.from.bodies(W.assemblies([owner0(),owner1(),owner2()],1),2048)
    M.emit(w)
    loop(90n,121,w)
'''
    return source


def check(text,config=None):
    batches=[];batch=[]
    for line in text.splitlines():
        row=read_json(line);batch.append(row)
        if row['record_type']=='complete':batches.append(batch);batch=[]
    require(text.endswith('\n') and not batch and len(batches)==91,'incomplete support reference execution')
    fixture=fixture_config(config)
    frozen=schedule(fixture)
    cut_frames=tuple(int(a['frame']) for a in frozen['actions'])
    import json
    states=[]
    for batch in batches:
        # Dense six-neighbor and exposed-unit-face oracle, independent of the
        # scalable sparse sweep used for district replay.
        bodies(batch[1:-1])
        state,_=initial_payload('\n'.join(map(json.dumps,batch)),frozen,'reference',fixture)
        states.append(state)
    ref=Reference(states[0],frozen)
    checks=[]
    for frame,actual in zip(range(121,211),states[1:]):
        actual['view'].update(frozen['frames'][frame]['camera'])
        actual['action_outcomes']=[{'accepted':True,'action':a['action'],'frame':a['frame'],'outcome':'accepted','removed_cells':'16','target_m':a['target_m']} for a in frozen['actions'] if int(a['frame'])<=frame]
        if frame in cut_frames:ref.cut(frozen['actions'][cut_frames.index(frame)],actual)
        diff=mismatch(ref.state(frame),actual)
        require(diff is None,'support runtime reference mismatch: '+str(diff))
        checks.append({'frame':str(frame),'sha256':digest(actual)})
    return {'status':'pass','frames':'90','released':ref.released,'checkpoints':checks,
            'scope':'actual Bend cuts and physics against dense connectivity/material/surfaces, analytic motion and exact binary32/floor reference'}
