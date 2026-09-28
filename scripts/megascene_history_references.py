"""Compact actual Bend replay checked with independent dense cell transitions."""
from megascene_recipe import Box, Owner, bend_program, f32, generate
from megascene_inventory import read_json, require
from megascene_picking import value
from megascene_references import dense, reference
from megascene_edit_references import bodies, real
from megascene_support import motion
from megascene_history import _target


TERRAIN=Owner('terrain_revisit',None,[Box((0,0,0),(20,1,20),1),Box((0,1,0),(20,4,20),2)])
SPAN=generate('small',45)[2]
MOVING=_target(5,{'preset':'small','seed':'45'})[-1]
ACTIONS={1:(.8,.2,.8),2:(1.1,.2,.8),3:(-29.5,4.,-14.),4:(-19.3,4.,-14.),
         16:tuple(map(value,MOVING))}


def program():
    source=bend_program([TERRAIN,SPAN],2048).split('def main()',1)[0].replace('./src/','./')
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
    for frame,point in ACTIONS.items():
        source+=f"        +w : W.World <- apply(U32.is_eq(frame,{frame}),w,R.Vec{{{','.join(map(real,point))}}})\n"
    source+='''        M.emit(w)
        loop(rest,(frame + 1 : U32),w)

def main() -> IO(Unit):
  do IO<Unit>:
    +w : W.World = W.from.bodies(W.assemblies([owner0(),owner1()],1),2048)
    M.emit(w)
    loop(20n,1,w)
'''
    return source


def _local(point,offset):
    return tuple(f32(f32(f32(p)-(offset if axis==1 else 0))*10) for axis,p in enumerate(point))


def _remaining(cells,center):
    return {p:m for p,m in cells.items() if m==1 or
            sum((axis+.5-target)**2 for axis,target in zip(p,center))>4.00001}


def check(text):
    batches=[];batch=[]
    for line in text.splitlines():
        row=read_json(line);batch.append(row)
        if row['record_type']=='complete': batches.append(batch);batch=[]
    require(text.endswith('\n') and not batch and len(batches)==21,'incomplete focused history reference replay')
    initial=bodies(batches[0][1:-1])
    require(initial['1'][1]==dense(TERRAIN.boxes) and initial['2'][1]==dense(SPAN.boxes),
            'focused reference inputs differ from independent cells')
    releases={};verified=[];first_damage=set()
    previous=initial;old_world=batches[0][0]
    for frame,batch in enumerate(batches[1:],1):
        world=batch[0];current=bodies(batch[1:-1])
        physics={}
        for ident,(body,cells) in previous.items():
            offset,speed=(motion(frame-release[0],release[1],release[2],release[3])
                          if (release:=releases.get(ident)) else (body['offset'],body['speed']))
            physics[ident]=(cells,offset,speed,body['anchored'])
        if frame in ACTIONS:
            point=ACTIONS[frame]
            untouched={};changed=[];removed=0;affected=[]
            for ident,(cells,offset,speed,anchored) in physics.items():
                center=_local(point,value(offset))
                keep=_remaining(cells,center)
                removed+=len(cells)-len(keep)
                if keep==cells: untouched[ident]=(cells,offset,speed,anchored)
                else:
                    affected.append((ident,offset,anchored,center))
                    if frame==1:first_damage=set(cells)-set(keep)
                    for group in reference(keep)[0]:
                        piece={p:keep[p] for p in group}
                        changed.append((piece,offset,speed,1 in piece.values()))
            require(removed>0,'focused required action became a no-op')
            if frame==2:
                require(any(sum((axis+.5-target)**2 for axis,target in zip(p,affected[0][3]))<=4.00001
                            for p in first_damage),'focused revisit did not overlap prior damage')
            if frame==16:
                require(len(affected)==1 and not affected[0][2] and value(affected[0][1])<0,
                        'focused moved-beam cut did not strike the released body')
            first=int(old_world['next_id'])
            require({int(i) for i in current if i not in untouched}==set(range(first,first+len(changed))),
                    'focused lifetime ID allocation mismatch')
            for ident,(body,cells) in current.items():
                if ident in untouched:
                    expected=untouched[ident]
                    require((cells,body['offset'],body['speed'],body['anchored'])==expected,
                            'focused unchanged body/motion mismatch')
                else:
                    matches=[part for part in changed if part[0]==cells]
                    require(len(matches)==1,'focused changed component material/connectivity mismatch')
                    _,offset,speed,anchored=matches[0]
                    require((body['offset'],body['speed'],body['anchored'])==(offset,speed,anchored),
                            'focused component inherited motion/anchor mismatch')
                    if not anchored:
                        releases[ident]=(frame,min(p[1] for p in cells),value(offset),value(speed))
            releases={ident:data for ident,data in releases.items() if ident in current}
            require(world['status']=='1' and world['removed']==str(removed) and
                    world['next_id']==str(first+len(changed)) and
                    int(world['cells'])==int(old_world['cells'])-removed,
                    'focused cut outcome/conservation mismatch')
            verified.append({'frame':str(frame),'removed_cells':str(removed),
                             'fragments':world['fragments'],'next_id':world['next_id']})
        else:
            require(set(current)==set(physics) and world['cells']==old_world['cells'] and
                    world['next_id']==old_world['next_id'],'focused unchanged frame mutated geometry')
            for ident,(body,cells) in current.items():
                require((cells,body['offset'],body['speed'],body['anchored'])==physics[ident],
                        'focused intermediate motion mismatch')
        require(world['fragments']==str(sum(not b['anchored'] for b,_ in current.values())),
                'focused fragment count mismatch')
        previous=current;old_world=world
    require(len(verified)==5 and verified[-1]['frame']=='16' and
            int(verified[-1]['removed_cells'])>0,'focused moved beam/revisit cut missing')
    return {'status':'pass','frames':'20','actions':verified,
            'scope':'actual Bend terrain revisit/support/moved-beam cuts against dense cells, positive-face components, surfaces, motion and IDs'}
