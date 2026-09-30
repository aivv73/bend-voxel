"""Six support cuts with independent components, binary32 motion and replay evidence.

Only the small span owners are expanded to cells. District geometry stays sparse.
No production connectivity, carving, motion or surface routine is called here.
"""
from functools import lru_cache
import math

from megascene_inventory import SCHEMA, digest, require, surface_reference
from megascene_recipe import Box, bits, f32, generate
from megascene_references import dense, reference
from megascene_localized import remove_cells, audit_actions
from megascene_checkpoints import occupancy, strings, surface, mismatch
from megascene_picking import value, exact_pick
from megascene_scale import side_count
from megascene_schedule import numeric, plan

CUT_FRAMES = tuple(121 + 6*i for i in range(6))
WINDOW = tuple(range(152, 164))


def boxes_of(body):
    return [Box((int(x0),int(y0),int(z0)),(int(x1),int(y1),int(z1)),int(m))
            for x0,x1,ys in body['occupancy'] for y0,y1,zs in ys for z0,z1,m in zs]


def components(boxes, target):
    keep,removed = remove_cells(boxes,target)
    cells = dense(keep)
    groups,_ = reference(cells)
    # Each sparse box is internally connected, so one member identifies its group.
    return [[b for b in keep if b.lo in group] for group in groups],removed


def geometry(boxes):
    return {'anchored':any(b.material == 1 for b in boxes),
            'occupancy':strings(occupancy(boxes)), 'surface':surface(surface_reference(boxes))}


@lru_cache(maxsize=256)
def motion(steps, bottom=42, offset=0., speed=0.):
    """Binary32 operations checked separately against the pre-contact parabola."""
    dt=f32(1/60)
    floor=f32(-f32(bottom*f32(.1)))
    start_offset,start_speed=offset,speed
    for _ in range(steps):
        y=f32(f32(offset+f32(speed*dt))-f32(f32(f32(4.905)*dt)*dt))
        offset=max(floor,y)
        speed=f32(speed-f32(f32(9.81)*dt)) if y>floor else 0.
        if y<=floor: break
    elapsed=steps*dt
    continuous=start_offset+start_speed*elapsed-9.81*elapsed*elapsed/2
    if offset>floor:
        require(abs(offset-continuous)<.0001 and abs(speed-(start_speed-9.81*elapsed))<.0001,
                'binary32 pre-contact motion differs from independent analytic reference')
    require(math.isfinite(offset) and math.isfinite(speed) and offset>=floor, 'invalid floor/motion reference')
    return bits(offset),bits(speed)


def ray_to(eye, point):
    return numeric('ray',*(float(x).hex() for x in (*eye,*point)))


def schedule(config):
    require((config['warmup'],config['frames']) == ('120','3600'), 'support requires the complete 120/3600 schedule')
    schedule_id=config.get('schedule','support-v1')
    routes={'support-v1','support-1-span-v1','support-2-span-v1','fill-support-v1'}
    require(schedule_id in routes and
            (schedule_id=='fill-support-v1')==(config.get('control')=='fill'),
            'unsupported support schedule')
    q=side_count(config['preset'])
    origin=-int(config['side_m'])*5
    require(origin==-160*q, 'support envelope differs from admitted district')
    frozen=plan('support',q,config['seed'],origin,config.get('control') or 'base',schedule_id)
    frozen.pop('_eye')
    owners=generate(config['preset'],int(config['seed']),config.get('control'))
    for i,action in enumerate(frozen['actions']):
        action.pop('_eye')
        target=[f32(value(x)*10) for x in action['target_m']]
        require(all(x==round(x) for x in target), 'inexact support target round trip')
        ray=action['pre_edit_ray']
        hit=exact_pick([(k,b,0.) for k,o in enumerate(owners,1) for b in o.boxes],
                       list(map(value,ray['origin_m'])),list(map(value,ray['direction'])))
        require(hit['owner']==action['source_owner'] and hit['kind']=='1' and hit['distance']<256,
                'support pre-edit target unreachable: '+str(i))
        boxes=owners[int(action['source_owner'])-1].boxes
        if i%2:
            prior=[f32(value(x)*10) for x in frozen['actions'][i-1]['target_m']]
            parts,_=components(boxes,prior)
            boxes=next(bs for bs in parts if sum(math.prod(b-a for a,b in zip(x.lo,x.hi)) for x in bs)>120)
        parts,removed=components(boxes,target)
        require(len(removed)==16 and set(removed.values())=={3}, 'support material removal mismatch')
        volumes=sorted(sum(math.prod(b-a for a,b in zip(x.lo,x.hi)) for x in bs) for bs in parts)
        require(len(parts)==2 and volumes[0]==120 and sum(not geometry(bs)['anchored'] for bs in parts)==i%2,
                'support connectivity reference mismatch')
        action['expected_removed_cells']=str(len(removed))
        action['pre_edit_hit']={k:str(v) for k,v in hit.items() if k!='point'}
        action['reference_removed_cells']=[[*map(str,p),str(m)] for p,m in sorted(removed.items())]
    return frozen


def action_outcome(action):
    return {k:action[k] for k in ('action','frame','target_m')} | {'accepted':True,'outcome':'accepted','removed_cells':'16'}




class Reference:
    """Match independently computed components to actual monotonic IDs at edits.

    Assignment within a split is an implementation detail. Its observed mapping
    is retained and compared with the separately validated timed replay.
    """
    def __init__(self,initial,frozen):
        self.initial=initial; self.frozen=frozen; self.states=[initial]; self.released={}

    def state(self,frame):
        phase=sum(int(a['frame'])<=frame for a in self.frozen['actions'])
        require(phase<len(self.states), 'missing preceding support component checkpoint')
        state=self.states[phase]
        bodies=[]
        for b in state['bodies']:
            release=self.released.get(b['id'])
            if release is not None:
                offset,speed=motion(frame-release['frame'],int(self.frozen.get('released_bottom_cells','42')))
                b={**b,'offset_m':offset,'velocity_m_s':speed}
            bodies.append(b)
        return {**state,'bodies':bodies,'view':{**state['view'],**self.frozen['frames'][frame]['camera']}}

    def cut(self,action,actual):
        frame=int(action['frame'])
        # Before this edit, physics has already advanced the earlier spans.
        before=self.state(frame-1)
        before={**before,'bodies':[dict(b,offset_m=motion(frame-self.released[b['id']]['frame'],int(self.frozen.get('released_bottom_cells','42')))[0],
                    velocity_m_s=motion(frame-self.released[b['id']]['frame'],int(self.frozen.get('released_bottom_cells','42')))[1]) if b['id'] in self.released else b for b in before['bodies']]}
        target=[f32(value(x)*10) for x in action['target_m']]
        source=next(b for b in before['bodies'] if b['anchored'] and any(all(a<=p<c for p,a,c in zip(target,box.lo,box.hi)) for box in boxes_of(b)))
        ray=action['pre_edit_ray']
        hit=exact_pick([(int(b['id']),box,value(b['offset_m'])) for b in before['bodies'] for box in boxes_of(b)],
                       list(map(value,ray['origin_m'])),list(map(value,ray['direction'])))
        require(hit['owner']==source['id'] and hit['kind']=='1' and hit['distance']<256, 'actual pre-edit support owner unreachable')
        parts,removed=components(boxes_of(source),target)
        require([[*map(str,p),str(m)] for p,m in sorted(removed.items())]==action['reference_removed_cells'], 'support exact removed material mismatch')
        fresh=[b for b in actual['bodies'] if int(b['id'])>=int(before['next_id'])]
        require({int(b['id']) for b in fresh}==set(range(int(before['next_id']),int(before['next_id'])+len(parts))), 'support component ID allocation mismatch')
        expected=[]
        for boxes in parts:
            shape=geometry(boxes)
            matches=[b for b in fresh if b['occupancy']==shape['occupancy']]
            require(len(matches)==1,'support component occupancy mismatch')
            body={**shape,'id':matches[0]['id'],'revision':'0','offset_m':source['offset_m'],'velocity_m_s':source['velocity_m_s']}
            expected.append(body)
            if not body['anchored']:
                require(int(action['action'])%2==1,'span detached after first support cut')
                require(min(b.lo[1] for b in boxes)==int(self.frozen.get('released_bottom_cells','42')),'released span lower bound mismatch')
                self.released[body['id']]={'span':action['span'],'frame':frame,'source_owner':action['source_owner']}
        state={**before,'bodies':sorted([b for b in before['bodies'] if b['id']!=source['id']]+expected,key=lambda b:int(b['id'])),
               'cells':str(int(before['cells'])-16),'removed':'16','status':'1','fragments':str(len(self.released)),
               'next_id':str(int(before['next_id'])+len(parts)),'action_outcomes':before['action_outcomes']+[action_outcome(action)]}
        self.states.append(state)
        require(mismatch(self.state(frame),actual) is None, 'support post-cut state/material/anchor/inherited motion mismatch: '+str(mismatch(self.state(frame),actual)))


def motion_records(records):
    result={}
    for r in records:
        if r['record_type']=='body_motion':
            key=(r['frame'],r['id'])
            require(key not in result,'duplicate body motion evidence')
            result[key]={k:r[k] for k in ('id','revision','offset_m','velocity_m_s')}
    return result


def audit_window(records,frozen):
    """Schedule completion requires actual released geometry and per-frame motion."""
    checks={r['frame']:r for r in records if r['record_type']=='checkpoint'}
    released={}
    for a in frozen['actions']:
        payload=checks[a['frame']]['payload']
        detached=[b for b in payload['bodies'] if not b['anchored']]
        if int(a['action'])%2:
            fresh=[b for b in detached if b['id'] not in released]
            require(len(fresh)==1,'missing distinct released span')
            b=fresh[0];span=int(a['span'])
            feature=list(map(int,frozen['beam_features'][span]['local_top_center_cells']))
            require(any(box.material==2 and all(lo<=p<hi for p,lo,hi in zip((feature[0],feature[1]-1,feature[2]),box.lo,box.hi)) for box in boxes_of(b)), 'released identity is not the intended span')
            released[b['id']]={'span':a['span'],'release_frame':a['frame']}
        require(len(detached)==(int(a['action'])+1)//2,'support path detached prematurely or not released')
    require(len(released)==int(frozen['moving_window']['distinct_spans']),
            'declared number of distinct span identities required')
    observed=motion_records(records);window=[]
    for i in WINDOW:
        cp=checks[str(i)]['payload']
        samples=[]
        for ident,release in released.items():
            body=next(b for b in cp['bodies'] if b['id']==ident)
            sample=observed[str(i),ident]
            offset,speed=motion(i-int(release['release_frame']),int(frozen.get('released_bottom_cells','42')))
            require(not body['anchored'] and value(speed)<0 and
                    (body['offset_m'],body['velocity_m_s'])==(offset,speed) and
                    sample=={k:body[k] for k in sample}, 'required moving window missing or motion incorrect')
            samples.append({**sample,'span':release['span']})
        window.append({'frame':str(i),'measured_ordinal':str(i-121),'bodies':samples,'sha256':checks[str(i)]['sha256']})
    return {'status':'pass','released':released,'frames':window}


def audit_details(records,frozen,required):
    captures=[r for r in records if r['record_type']=='detail_capture']
    rendered=[r for r in records if r['record_type']=='detail_render']
    if not required:
        require(not captures and not rendered,'supplementary captures entered timed execution')
        return
    require(len(captures)==len(frozen['supplementary_views']),'missing supplementary cut captures')
    for planned,actual in zip(frozen['supplementary_views'],captures):
        require(actual['rendered_frame']==planned['frame'] and actual['action']==planned['action'] and
                actual['camera']==planned['camera'], 'supplementary cut capture/view mismatch')
        primary=next(r for r in records if r['frame']==planned['frame'] and r['record_type']=='native_audit')
        work=next(r for r in records if r['frame']==planned['frame'] and r['record_type']=='render_work')
        for phase in ('closeup','restore'):
            rs=[r['evidence'] for r in rendered if r['rendered_frame']==planned['frame'] and r['phase']==phase]
            ns=[r for r in rs if r['record_type']=='native_audit'];ws=[r for r in rs if r['record_type']=='render_work']
            require(len(ns)==len(ws)==1,'missing supplementary native/cache evidence')
            n,w=ns[0],ws[0]
            for key in ('mesh_slots','proxy_cache_sha256','vertices_checked') + (('mesh_sha256',) if 'mesh_sha256' in primary else ()):
                require(n[key]==primary[key], 'supplementary rendering changed '+key)
            require(w['mesh_rebuilt']==w['proxy_rebuilt']=='0' and w['shadow_refresh'] is False and w['shadow_body_draws']=='0',
                    'supplementary view rebuilt geometry/shadows')
            for key in ('body_count','full_meshes','shadow_extent_m','shadow_texel_m','shadow_fit_min_margin_texels'):
                require(w[key]==work[key], 'supplementary view changed '+key)
            require(int(n['reference_visible'])<=len(n['drawn_ids'])+len(n.get('proxied_ids',[])) and str(len(n['drawn_ids']))==w['main_body_draws'],'supplementary visibility mismatch')
            if phase=='restore':
                require(n['drawn_ids']==primary['drawn_ids'], 'frozen overview not restored')
                for key in ('selected_ids','proxied_ids','proxy_group_evidence'):
                    if key in primary:
                        require(n.get(key)==primary[key], 'supplementary restoration changed '+key)
                for key in ('proxy_draws','proxied_bodies','main_body_draws','visible_bodies'):
                    if key in work:
                        require(w.get(key)==work[key], 'supplementary restoration changed '+key)
    require({r['rendered_frame'] for r in rendered}=={v['frame'] for v in frozen['supplementary_views']} and
            all(r['phase'] in ('closeup','restore') for r in rendered),'unexpected supplementary render')


def audit(records,frozen,initial,initial_work,complete,thorough=False):
    failures=[];catalog=[];checked=set();phase_work=[];window=None;features=[]
    try:
        require(complete,'complete declared support schedule unavailable')
        audit_actions(records,frozen)
        audit_details(records,frozen,thorough)
        ref=Reference(initial,frozen)
        checks=[r for r in records if r['record_type'] in ('checkpoint','static_audit')]
        by_frame={r['frame']:r for r in checks}
        require(len(by_frame)==len(checks),'duplicate checkpoint frame')
        previous_work=initial_work
        cut_frames={int(a['frame']) for a in frozen['actions']}
        for action in frozen['actions']:
            cp=by_frame[action['frame']]
            ref.cut(action,cp['payload'])
            work=cp['work'];before=ref.states[-2];after=ref.states[-1]
            shared={b['id'] for b in before['bodies']} & {b['id'] for b in after['bodies']}
            require([w for w in work if w['id'] in shared]==[w for w in previous_work if w['id'] in shared], 'unaffected body representation changed')
            require({w['id'] for w in work}=={b['id'] for b in after['bodies']} and len(work)==len(after['bodies']), 'component work inventory missing/duplicate')
            for b in after['bodies']:
                w=next(w for w in work if w['id']==b['id'])
                boxes=boxes_of(b)
                require(w['cells']==str(sum(math.prod(y-x for x,y in zip(b.lo,b.hi)) for b in boxes)) and
                        w['protected_cells']==str(sum(math.prod(y-x for x,y in zip(b.lo,b.hi)) for b in boxes if b.material==1)), 'component cell/anchor inventory mismatch')
            phase_work.append(work);previous_work=work
        states={};hashes={};body_hashes={}
        def expected_at(i):
            # Reuse stationary payloads after the last floor contact.
            key=i if i<212 else 212
            if key not in states:
                s=ref.state(key);states[key]=s;hashes[key]=digest(s);body_hashes[key]={b['id']:digest(b) for b in s['bodies']}
            return states[key],hashes[key],body_hashes[key]
        points={p['name']:p['frame'] for p in frozen['required_checkpoints']}
        for r in checks:
            frame=r['frame'];i=int(frame);checked.add(frame)
            names=[name for name,at in points.items() if at==frame]
            require(r['names']==names and r['record_type']==('checkpoint' if names else 'static_audit') and ('payload' in r)==bool(names), 'checkpoint kind/name/payload mismatch')
            state,sha,bs=expected_at(i)
            if names:
                diff=mismatch(state,r['payload'])
                require(diff is None,'support state mismatch: '+str(diff))
                require(digest(r['payload'])==r['sha256'],'checkpoint digest mismatch')
            require(r['sha256']==sha and r['body_sha256']==bs,'support state/geometry mismatch at frame '+frame)
            phase=sum(f<=i for f in cut_frames)
            require(r['work']==([initial_work]+phase_work)[phase],'representation changed during translation')
            catalog += [{'name':name,'frame':frame,'sha256':sha,'body_sha256':bs} for name in names]
        require(checked==({f['frame'] for f in frozen['frames']} if thorough else set(points.values())), 'incomplete support checkpoint replay')
        window=audit_window(records,frozen)
        observed=motion_records(records);expected_motion={}
        native=[r for r in records if r['record_type']=='native_audit']
        rendered=[r for r in records if r['record_type']=='render_work']
        frames=[r for r in records if r['record_type']=='frame']
        require(len(native)==len(rendered)==len(frames)==3721,'incomplete support native replay')
        previous=None;previous_native=None;previous_state=None
        for i,(n,w,f) in enumerate(zip(native,rendered,frames)):
            require(n['frame']==w['frame']==f['frame']==str(i),'native/frame order mismatch')
            state,_,_=expected_at(i);ids={b['id'] for b in state['bodies']}
            for b in state['bodies']:
                if not b['anchored']: expected_motion[str(i),b['id']]={k:b[k] for k in ('id','revision','offset_m','velocity_m_s')}
            phase=sum(at<=i for at in cut_frames);work=([initial_work]+phase_work)[phase]
            require(len(n['drawn_ids'])==len(set(n['drawn_ids'])) and set(n['drawn_ids'])<=ids and str(len(n['drawn_ids']))==w['main_body_draws'] and int(n['reference_visible'])<=len(n['drawn_ids']), 'native visible geometry missing')
            require(int(n['vertices_checked'])==sum(int(b['vertices']) for b in work),'incomplete native mesh checks')
            require(set(n['mesh_sha256'])==ids,'missing native full-mesh hashes')
            require(w['mesh_rebuilt']==(str(len(ids)) if i==0 else '2' if i in cut_frames else '0'),'translation rebuilt local geometry')
            changed=i==0 or i in cut_frames or any(b['offset_m']!=next(old['offset_m'] for old in previous_state['bodies'] if old['id']==b['id']) for b in state['bodies'])
            require(w['shadow_refresh'] is changed and w['shadow_body_draws']==(str(len(ids)) if changed else '0'), 'moving body shadow invalidation mismatch')
            require(value(w['shadow_fit_min_margin_texels'])>=0 and all(value(x)>0 for x in w['shadow_texel_m']), 'shadow fit missing occupied geometry')
            if previous:
                for ident in ids & set(previous_native['mesh_slots']):
                    require(n['mesh_slots'][ident]==previous_native['mesh_slots'][ident] and n['mesh_sha256'][ident]==previous_native['mesh_sha256'][ident], 'unchanged full-mesh slot/data changed')
                if i not in cut_frames:
                    require(n['proxy_cache_sha256']==previous_native['proxy_cache_sha256'] and w['proxy_rebuilt']=='0', 'translation invalidated proxy cache')
            if i in (152,163):
                for ident,release in ref.released.items():
                    require(ident in n['drawn_ids'],'required released span not visible')
                    b=next(b for b in state['bodies'] if b['id']==ident)
                    feature=frozen['beam_features'][int(release['span'])]
                    point=[f32(f32(int(x)*f32(.1))+(value(b['offset_m']) if k==1 else 0)) for k,x in enumerate(feature['local_top_center_cells'])]
                    eye=list(map(value,state['view']['eye_m']));ray=ray_to(eye,point)
                    hit=exact_pick([(int(body['id']),box,value(body['offset_m'])) for body in state['bodies'] for box in boxes_of(body)],eye,list(map(value,ray['direction'])))
                    require(hit['owner']==ident,'beam top-center occluded or assigned to wrong body')
                    features.append({'frame':str(i),'name':'beam_'+release['span']+'_top_center','body_id':ident,'position_m':list(map(bits,point)),
                                     'offset_m':b['offset_m'],'velocity_m_s':b['velocity_m_s'],'visible':True,'mesh_sha256':n['mesh_sha256'][ident]})
            previous=w;previous_native=n;previous_state=state
        require(observed==expected_motion,'missing, extra or incorrect actual per-body motion evidence')
        for r in records:
            if r['record_type']=='presentation_status':
                require(r['result']=='1000001003' and r['frozen_surface_unchanged'] is True,'presentation changed')
    except (ValueError,KeyError,TypeError,StopIteration,IndexError) as exc:
        failures.append({'reason':str(exc) or 'missing required support evidence'})
    return {'schema':SCHEMA,'record_type':'checkpoint_comparison','synthetic':any(r.get('synthetic',False) for r in records),
        'status':'fail' if failures else 'pass','failures':failures,'checkpoints':catalog,'checked_frames':str(len(checked)),
        'native_frames':str(sum(r['record_type']=='native_audit' for r in records)),'actual_work':initial_work,
        'edited_work':phase_work,'moving_window':window,'beam_features':features,
        'scope':'independent support components/material/anchors, motion/floor and full-mesh/shadow replay'}
