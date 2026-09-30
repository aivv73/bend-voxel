"""One frozen terrain cut, independent sparse removal and evolving replay audit."""
from itertools import product
import math

from megascene_inventory import SCHEMA, connected, digest, require, surface_reference
from megascene_recipe import Box, f32, generate
from megascene_picking import checked_result, value
from megascene_scale import side_count
from megascene_schedule import plan


def remove_cells(boxes, target):
    """Enumerate only the small brush neighborhood, then subtract unit cells.

    No production split, tree traversal or local surface patching is reused.
    Protected material and all distant sparse boxes stay in the reference.
    """
    removed = {}
    for point in product(*(range(math.floor(p-2), math.ceil(p+2)) for p in target)):
        if sum((x+.5-p)**2 for x,p in zip(point,target)) > 4.00001:
            continue
        for box in boxes:
            if box.material != 1 and all(a<=x<b for x,a,b in zip(point,box.lo,box.hi)):
                require(point not in removed, "overlapping cut ownership")
                removed[point] = box.material
    result = list(boxes)
    for point in sorted(removed):
        fresh=[]
        for box in result:
            if not all(a<=x<b for x,a,b in zip(point,box.lo,box.hi)):
                fresh.append(box)
                continue
            lo,hi=list(box.lo),list(box.hi)
            for axis in range(3):
                if lo[axis]<point[axis]:
                    upper=hi.copy(); upper[axis]=point[axis]
                    fresh.append(Box(tuple(lo),tuple(upper),box.material)); lo[axis]=point[axis]
                if point[axis]+1<hi[axis]:
                    lower=lo.copy(); lower[axis]=point[axis]+1
                    fresh.append(Box(tuple(lower),tuple(hi),box.material)); hi[axis]=point[axis]+1
        result=fresh
    return result,removed


def schedule(config):
    require((config['warmup'],config['frames']) == ('120','3600'), 'localized requires the complete 120/3600 schedule')
    require(config.get('schedule','localized-v1') in ('localized-v1','material-detail-localized-v1'), 'unsupported localized schedule')
    frozen=plan('localized',side_count(config['preset']),config['seed'],-int(config['side_m'])*5,
                config.get('control') or 'base',config.get('schedule','localized-v1'))
    action=frozen['actions'][0]
    action.pop('_eye')
    target=[f32(value(x)*10) for x in action['target_m']]
    require(all(x==round(x) for x in target), 'inexact localized target round trip')
    owners=generate(config['preset'],int(config['seed']),config.get('control'))
    hit,reference=checked_result([(i,b,0.) for i,o in enumerate(owners,1) for b in o.boxes],action['pre_edit_ray'])
    require((hit['owner'],hit['material'],hit['kind']) == ('1','2','1') and reference['distance']<256,
            'localized pre-edit terrain target unreachable')
    remaining,removed=remove_cells(owners[0].boxes,target)
    expected_materials = {2,5} if config.get('control') == 'material-detail' else {2}
    require(len(removed)==16 and set(removed.values())==expected_materials and connected(remaining), 'localized removal/reference mismatch')
    action['expected_removed_cells']=str(len(removed))
    action['pre_edit_hit']=hit
    frozen['reference_removed_cells']=[[*map(str,p),str(m)] for p,m in sorted(removed.items())]
    return frozen


def action_outcome(frozen):
    a=frozen['actions'][0]
    return {'accepted':True,'action':'0','frame':'121','outcome':'accepted','removed_cells':a['expected_removed_cells'],'target_m':a['target_m']}


def edited_payload(initial,frozen):
    from megascene_checkpoints import occupancy,strings,surface
    # Expand canonical strips to sparse boxes, never the district's dense cells.
    terrain=next(b for b in initial['bodies'] if b['id']=='1')
    boxes=[Box((int(x0),int(y0),int(z0)),(int(x1),int(y1),int(z1)),int(m))
           for x0,x1,ys in terrain['occupancy'] for y0,y1,zs in ys for z0,z1,m in zs]
    target=[f32(value(x)*10) for x in frozen['actions'][0]['target_m']]
    boxes,removed=remove_cells(boxes,target)
    require([[*map(str,p),str(m)] for p,m in sorted(removed.items())] == frozen['reference_removed_cells'], 'initial cut material/occupancy mismatch')
    require(connected(boxes), 'localized reference disconnected terrain')
    body={**terrain,'id':initial['next_id'],'revision':'0','occupancy':strings(occupancy(boxes)),
          'surface':surface(surface_reference(boxes))}
    return {**initial,'bodies':sorted([b for b in initial['bodies'] if b['id']!='1']+[body],key=lambda b:int(b['id'])),
            'cells':str(int(initial['cells'])-len(removed)),'removed':str(len(removed)),
            'status':'1','next_id':str(int(initial['next_id'])+1),'action_outcomes':[action_outcome(frozen)]}


def expected_payload(initial,edited,frame):
    state=edited if int(frame['frame'])>=121 else initial
    return {**state,'view':{**state['view'],**frame['camera']}}


def audit_actions(records,frozen):
    """Required edits share exact action and CPU interval contracts."""
    actions=[r for r in records if r['record_type']=='action']
    begins=[r for r in records if r['record_type']=='edit_begin']
    edits=[r for r in records if r['record_type']=='edit']
    required=frozen['actions']
    require(len(actions)==len(begins)==len(edits)==len(required),'required action/edit interval count mismatch')
    removed=0
    for planned,a,b,e in zip(required,actions,begins,edits):
        expected={k:planned[k] for k in ('action','frame','target_m')} | {
            'accepted':True,'outcome':'accepted','removed_cells':planned['expected_removed_cells']}
        require(a['outcome']==expected,'required cut rejected, no-op, or incorrect removal')
        require(all(r['frame']==planned['frame'] and r['action']==planned['action'] for r in (a,b,e)), 'action frame/identity mismatch')
        require(all(r['accepted'] is True and r['removed_cells']==expected['removed_cells'] for r in (a,e)), 'required action was not accepted')
        frame=next(r for r in records if r['record_type']=='frame' and r['frame']==planned['frame'])
        require(e['begin_ns']==b['begin_ns'] and e['end_ns']==frame['end_ns'] and
                int(frame['begin_ns'])<=int(e['begin_ns'])<=int(e['end_ns']), 'edit interval boundary mismatch')
        require(int(e['duration_ns'])==int(e['end_ns'])-int(e['begin_ns']), 'edit interval duration mismatch')
        stages=[r for r in records if r['record_type']=='stage' and r['frame']==planned['frame']]
        ordered=[next(r for r in stages if r['stage']==name) for name in ('physics','carve','connectivity','surfaces','commit','view')]
        require(all(int(x['end_ns'])<=int(y['begin_ns']) for x,y in zip(ordered,ordered[1:])), 'physics/edit/view order mismatch')
        require(int(ordered[0]['end_ns'])<=int(e['begin_ns'])<=int(ordered[1]['begin_ns']), 'edit begins outside scripted operation')
        removed+=int(expected['removed_cells'])
    return {'status':'pass','actions':str(len(actions)),'accepted_edits':str(len(actions)),
            'removed_cells':str(removed),'ordinary_frames':str(sum(f['phase']=='ordinary' for f in frozen['frames']))}


def audit(records,frozen,initial,initial_work,complete,thorough=False,validated_work=None):
    from megascene_checkpoints import mismatch,checkpoint_bytes
    import hashlib
    failures=[];catalog=[];seen=set();checked=set()
    try:
        require(complete,'complete declared schedule unavailable')
        audit_actions(records,frozen)
        edited=edited_payload(initial,frozen)
        points={p['name']:p['frame'] for p in frozen['required_checkpoints']}
        checks=[r for r in records if r['record_type'] in ('checkpoint','static_audit')]
        post=next(r['work'] for r in checks if r['frame']=='121')
        if validated_work is not None:
            require(post==validated_work,'post-edit representation differs from validation')
        unchanged=[w for w in initial_work if w['id']!='1']
        require([w for w in post if w['id']!=initial['next_id']]==unchanged,'unaffected body work changed')
        new=next(w for w in post if w['id']==initial['next_id'])
        old=next(w for w in initial_work if w['id']=='1')
        require(new['cells']==str(int(old['cells'])-16) and new['protected_cells']==old['protected_cells'],'edit work/material conservation mismatch')
        states = [expected_payload(initial,edited,frozen['frames'][i]) for i in (0,121)]
        hashes = [digest(s) for s in states]
        body_hashes = [{b['id']:digest(b) for b in s['bodies']} for s in states]
        for r in checks:
            frame=r['frame'];require(frame not in checked,'duplicate checkpoint frame');checked.add(frame)
            names=[name for name,at in points.items() if at==frame]
            require(r['names']==names and r['record_type']==('checkpoint' if names else 'static_audit'), 'checkpoint kind/name schedule mismatch')
            require(('payload' in r)==bool(names), 'required canonical checkpoint payload missing')
            phase=int(int(frame)>=121)
            expected=states[phase]
            bodies=body_hashes[phase]
            if 'payload' in r:
                diff=mismatch(expected,r['payload'])
                if diff: failures.append({'frame':frame,**diff})
                require(hashlib.sha256(checkpoint_bytes(r['payload'])).hexdigest()==r['sha256'],'checkpoint digest mismatch')
            require(r['sha256']==hashes[phase] and r['body_sha256']==bodies,'state/geometry mismatch at frame '+frame)
            require(r['work']==(initial_work if int(frame)<121 else post),'unexpected work refresh at frame '+frame)
            for name in r['names']:
                require(name not in seen and points.get(name)==frame,'unexpected checkpoint name/frame');seen.add(name)
                catalog.append({'name':name,'frame':frame,'sha256':r['sha256'],'body_sha256':r['body_sha256']})
        require(seen==set(points),'missing action/review checkpoint')
        require(checked==({f['frame'] for f in frozen['frames']} if thorough else set(points.values())), 'incomplete checkpoint replay')
        native=[r for r in records if r['record_type']=='native_audit']
        rendered=[r for r in records if r['record_type']=='render_work']
        frames=[r for r in records if r['record_type']=='frame']
        require(len(native)==len(rendered)==len(frames)==3721,'incomplete native replay')
        previous=None;previous_native=None
        for i,(n,w,f) in enumerate(zip(native,rendered,frames)):
            require(n['frame']==w['frame']==f['frame']==str(i),'native/frame order mismatch')
            state=initial if i<121 else edited;work=initial_work if i<121 else post
            ids={b['id'] for b in state['bodies']}
            require(len(n['drawn_ids'])==len(set(n['drawn_ids'])) and set(n['drawn_ids'])<=ids,'invalid native ownership')
            require(str(len(n['drawn_ids']))==w['main_body_draws'] and int(n['reference_visible'])<=len(n['drawn_ids']),'native visible geometry missing')
            require(int(n['vertices_checked'])==sum(int(b['vertices']) for b in work),'incomplete native mesh checks')
            require(w['mesh_rebuilt']==(str(len(ids)) if i==0 else '1' if i==121 else '0'),'unnecessary/missing mesh rebuild')
            require(w['shadow_refresh'] is (i in (0,121)) and w['shadow_body_draws']==(str(len(ids)) if i in (0,121) else '0'),'shadow invalidation mismatch')
            if previous:
                require(n['proxy_cache_sha256']==previous_native['proxy_cache_sha256'], 'unaffected proxy contents changed')
                for ident,slot in previous_native['mesh_slots'].items():
                    if ident in n['mesh_slots']:
                        require(n['mesh_slots'][ident]==slot, 'unaffected native mesh slot changed')
                require(w['proxy_rebuilt']=='0','unaffected proxy cache refreshed')
                for key in ('proxy_groups','proxy_vertices','shadow_extent_m','shadow_texel_m'):
                    require(w[key]==previous[key],key+' changed unexpectedly')
            previous=w;previous_native=n
        for r in records:
            if r['record_type']=='presentation_status':
                require(r['result']=='1000001003' and r['frozen_surface_unchanged'] is True,'presentation changed')
    except (ValueError,KeyError,TypeError,StopIteration) as exc:
        failures.append({'reason':str(exc) or 'missing required action evidence'})
    return {'schema':SCHEMA,'record_type':'checkpoint_comparison','synthetic':any(r.get('synthetic',False) for r in records),
            'status':'fail' if failures else 'pass','failures':failures,'checkpoints':catalog,'checked_frames':str(len(checked)),
            'native_frames':str(sum(r['record_type']=='native_audit' for r in records)), 'actual_work':initial_work,
            'edited_work':locals().get('post'), 'scope':'localized removal/material/ownership/surface and every native frame'}
