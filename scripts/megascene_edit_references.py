"""Independent dense edit, ownership, surface and exact rollback fixtures."""
from itertools import product
from megascene_inventory import coordinate, integer, read_json, require, verify_vertices
from megascene_recipe import Box, Owner, bend_program, f32
from megascene_references import dense, reference


def fixtures():
    remote=Owner('unaffected',None,[Box((20,0,0),(22,2,2),1),Box((22,0,0),(23,1,1),5)])
    return [
        ('signed_partial_protected',[Owner('cut',None,[Box((-4,-2,-2),(-2,2,2),1),Box((-2,-1,-1),(4,2,2),2),Box((0,2,0),(2,4,2),3)]),remote],(-.05,.15,.05),8,0.,0.,2),
        ('budget_rollback',[Owner('bar',None,[Box((-6,100,0),(5,101,1),2)]),remote],(-.05,9.05,.05),1,-1.,-2.,1),
        ('moving_split',[Owner('bar',None,[Box((-6,100,0),(5,101,1),2)]),remote],(-.05,9.05,.05),2,-1.,-2.,1),
        ('protected_noop',[Owner('anchor',None,[Box((-2,-2,-2),(2,2,2),1)]),remote],(0.,0.,0.),0,0.,0.,1),
        ('air_noop',[Owner('anchor',None,[Box((-2,-2,-2),(2,2,2),1)]),remote],(1.,1.,1.),0,0.,0.,1),
        ('complete_removal',[Owner('one',None,[Box((-1,10,0),(0,11,1),4)]),remote],(-.05,1.05,.05),1,0.,0.,1),
    ]


def real(x):
    return f'(0.0 - {abs(x)!r} : F32)' if x<0 else repr(float(x))


def program():
    fixtures_=fixtures();owners=[o for _,os,_,_,_,_,_ in fixtures_ for o in os]
    source=bend_program(owners,2048).split('def main()',1)[0].replace('./src/','./')
    source=source.replace('import Base','import Base\nimport ./megascene_edit.bend as E')
    source+='''
def pose(bs: List<&2,W.Body>, +offset: F32, +speed: F32) -> List<&2,W.Body>:
  match bs:
    case Nil{}: Nil{}
    case W.Body{id,_,_,_,a,t,fs,vs} <> rest:
      W.Body{id,7,offset,speed,a,t,fs,vs} <> rest

def identity(world: W.World) -> W.World:
  W.World{bs,n,c,r,s,_,b} = world
  W.World{bs,n,c,r,s,400,b}

def fixture(bs: List<&2,W.Body>, budget: U32, offset: F32, speed: F32) -> W.World:
  identity(W.from.bodies(pose(bs,offset,speed),budget))

def apply(+world: W.World, +point: R.Vec) -> IO(W.World):
  do IO<W.World>:
    E.guard(world,point)
    +next : W.World <- IO.pure(W.World,W.carve(world,point))
    M.emit(next)
    return next

def main() -> IO(Unit):
  do IO<Unit>:
'''
    at=0
    for name,os,point,budget,offset,speed,repeats in fixtures_:
        source+=f"    +w : W.World = fixture(W.assemblies([{','.join(f'owner{i}()' for i in range(at,at+len(os)))}],1),{budget},{real(offset)},{real(speed)})\n    M.emit(w)\n"
        for repeat in range(repeats):
            source+=f"    +w : W.World <- apply(w,R.Vec{{{','.join(map(real,point))}}})\n"
        at+=len(os)
    source+='    return Unit{}\n'
    return source


def bodies(records):
    result={}
    for body in records:
        cells=dense([Box(tuple(map(coordinate,b[:3])),tuple(map(coordinate,b[3:6])),integer(b[6])) for b in body['boxes']])
        groups,exposed=reference(cells)
        require(len(groups)==1 and body['connected'] is True,'reference owner disconnected')
        require(body['anchored'] is (1 in cells.values()),'reference anchor mismatch')
        drawn={};faces=[]
        for f in body['faces']:
            lo,hi=tuple(map(coordinate,f[:3])),tuple(map(coordinate,f[3:6]));side,material=integer(f[6]),integer(f[7]);axis=side//2
            faces.append((lo,hi,side,material))
            require(side<6 and lo[axis]==hi[axis],'nonplanar edit surface')
            for p in product(*(range(lo[k],hi[k]) if k!=axis else [lo[k]-side%2] for k in range(3))):
                require((p,side) not in drawn,'duplicate edit surface');drawn[p,side]=material
        require(drawn==exposed,'local rebuilding differs from dense exposed surfaces')
        verify_vertices(faces,body['vertices'])
        require(body['cells']==str(len(cells)),'body cell count mismatch')
        require(body['id'] not in result,'duplicate owner')
        result[body['id']]=(body,cells)
    return result


def check(text):
    from megascene_picking import value
    worlds=[];batch=[]
    for line in text.splitlines():
        r=read_json(line)
        if r['record_type']=='complete': worlds.append(batch);batch=[]
        else: batch.append(r)
    require(text.endswith('\n') and not batch and len(worlds)==sum(1+f[-1] for f in fixtures()),'incomplete edit reference stream')
    results=[];index=0
    for name,owners,point,budget,offset,speed,repeats in fixtures():
        before=worlds[index];index+=1
        initial=bodies(before[1:])
        require(set(initial)=={str(i) for i in range(1,len(owners)+1)}, 'initial fixture ownership mismatch')
        for ident,owner in enumerate(owners,1):
            require(initial[str(ident)][1]==dense(owner.boxes), 'initial fixture differs from independent source')
        for attempt in range(repeats):
            after=worlds[index];index+=1
            old,new=bodies(before[1:]),bodies(after[1:])
            expected=[];unchanged={};removed=0
            for ident,(body,cells) in old.items():
                local=[f32(f32(f32(x)-(value(body['offset']) if k==1 else 0))*10) for k,x in enumerate(point)]
                keep={p:m for p,m in cells.items() if m==1 or sum((x+.5-c)**2 for x,c in zip(p,local))>4.00001}
                removed+=len(cells)-len(keep)
                if keep==cells: unchanged[ident]=body
                else:
                    groups,_=reference(keep)
                    expected += [(body,{p:keep[p] for p in group}) for group in groups]
            fragments=sum(not b['anchored'] for b in unchanged.values())+sum(1 not in c.values() for _,c in expected)
            status='2' if not removed else '3' if fragments>budget else '1'
            require(after[0]['status']==status,'wrong reference edit outcome')
            if status!='1':
                require(before[1:]==after[1:],'rollback/no-op changed exact body geometry, IDs, revisions, materials, anchors or motion')
                require({k:v for k,v in before[0].items() if k not in ('removed','status')}=={k:v for k,v in after[0].items() if k not in ('removed','status')},'rollback/no-op changed world budget/next ID/counts')
                require(after[0]['removed']=='0','rejected/no-op removal telemetry')
            else:
                for ident,body in unchanged.items(): require(new[ident][0]==body,'unaffected cached body changed')
                fresh=[(b,c) for ident,(b,c) in new.items() if ident not in unchanged]
                require({int(b['id']) for b,_ in fresh}==set(range(int(before[0]['next_id']),int(before[0]['next_id'])+len(expected))),'new identity allocation mismatch')
                require(len(fresh)==len(expected),'component count mismatch')
                for b,c in fresh:
                    matches=[old for old,want in expected if c==want]
                    require(len(matches)==1,'changed ownership/material mismatch')
                    require(b['offset']==matches[0]['offset'] and b['speed']==matches[0]['speed'] and b['revision']=='0','component motion/revision mismatch')
                require(after[0]['removed']==str(removed) and after[0]['cells']==str(int(before[0]['cells'])-removed) and after[0]['fragments']==str(fragments),'edit conservation mismatch')
                require(after[0]['next_id']==str(int(before[0]['next_id'])+len(expected)) and after[0]['budget']==before[0]['budget'],'edit next ID/budget mismatch')
            results.append({'name':name,'attempt':str(attempt),'outcome':status,'removed_cells':after[0]['removed'],'status':'pass'})
            before=after
    return {'status':'pass','scope':'independent dense removal/material/components/surfaces and exact atomic rollback; runtime evidence','fixtures':results}
