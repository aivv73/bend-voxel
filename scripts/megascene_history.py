"""Frozen irregular history and an evolving sparse occupancy preflight.

The preflight is independent of Bend carving and connectivity. It follows
ownership and motion after each cut; the runtime checkpoint audit below uses
the same reference transitions against every observed edit.
"""
from dataclasses import dataclass
from copy import copy
import math

from megascene_inventory import SCHEMA, require, digest, surface_reference
from megascene_recipe import bits, f32, generate, Box
from megascene_scale import side_count, history_stride, history_visit
from megascene_localized import remove_cells, audit_actions as _audit_actions
from megascene_picking import value, exact_pick
from megascene_support import motion, ray_to, boxes_of, motion_records
from megascene_traversal import camera, pose
from megascene_checkpoints import occupancy, strings, surface, mismatch


CUT_FRAMES = tuple(121 + 12*k for k in range(120))
NAMED = ((12, 253), (48, 685), (120, 1549))
_SCHEDULE_CACHE = {}


def _touch(a, b):
    return any((a.hi[k] == b.lo[k] or b.hi[k] == a.lo[k]) and
               all(max(a.lo[t], b.lo[t]) < min(a.hi[t], b.hi[t]) for t in range(3) if t != k)
               for k in range(3))


def components(boxes):
    """Positive-face components of sparse, disjoint reference boxes."""
    unseen = set(range(len(boxes)))
    groups = []
    while unseen:
        group = {min(unseen)}
        unseen -= group
        pending = list(group)
        while pending:
            source = boxes[pending.pop()]
            found = [j for j in unseen if _touch(source, boxes[j])]
            unseen.difference_update(found)
            pending.extend(found)
            group.update(found)
        groups.append([boxes[j] for j in sorted(group)])
    return groups


@dataclass
class Body:
    ident: int
    boxes: list
    anchored: bool
    release: int | None = None
    offset: str = '0x00000000'
    speed: str = '0x00000000'
    bottom: int = 0
    start_offset: str = '0x00000000'
    start_speed: str = '0x00000000'

    def moved(self, frame):
        if self.release is not None:
            self.offset, self.speed = motion(frame-self.release, self.bottom,
                                             value(self.start_offset),value(self.start_speed))


def _origin(n, preset):
    q = side_count(preset)
    return (320*(n%q)-160*q, 320*(n//q)-160*q)


def _target(k, config):
    q = side_count(config['preset'])
    nhood = q*q
    b, a = divmod(k, 10)
    n, r = history_visit(b,nhood,int(config['seed']))
    ix, iz = n%q, n//q
    v = (3*ix+5*iz+int(config['seed'])-45)%4
    ox, oz = _origin(n,config['preset'])
    z = 176+24*r
    beam = 72+v
    top = 58+v%2
    local = ((160+12*r,24,160+8*r),(18,48,48+12*r),(25,40,z+4),
             (163+12*r,24,160+8*r),(127,40,z+4),None,
             ((40+3*r,48,134) if config.get('control') == 'body-rich' else (78,48,54+3*r)),
             (284+3*r,top,180+3*r),
             ((236,230,226)[r],23,272),((276,282,286)[r],23,272))[a]
    lift = 8 if config.get('control') == 'fill' else 0
    if a == 5:
        offset = value(motion(12,42+lift)[0])
        target = [bits(f32((76+ox)*f32(.1))),
                  bits(f32(f32((beam+2+lift)*f32(.1))+offset)),
                  bits(f32((z+4+oz)*f32(.1)))]
    else:
        target = [bits(x/10) for x in (local[0]+ox,local[1]+lift,local[2]+oz)]
    return n,r,a,v,local,target


def _view(a, n, r, v, local, target, config):
    ox, oz = _origin(n,config['preset'])
    point = list(map(value,target))
    lift = .8 if config.get('control') == 'fill' else 0
    if a in (0,3): eye = [point[0],point[1]+2,point[2]+1]
    elif a == 1: eye = [(8+ox)/10,4.8+lift,point[2]]
    elif a in (2,4): eye = [point[0],4.+lift,(176+24*r+16+oz)/10]
    elif a == 5: eye = [point[0],point[1]+2,point[2]+1.2]
    elif a == 6: eye = [((40+3*r if config.get('control')=='body-rich' else 100)+ox)/10,4.8+lift,
                         (120+oz)/10 if config.get('control')=='body-rich' else point[2]]
    elif a == 7: eye = [point[0],(58+v%2+32)/10+lift,point[2]-2]
    else: eye = [point[0],4.4+lift,(256+oz)/10]
    return camera(eye,point), eye


def _source(bodies, target, frame):
    hits=[]
    for body in bodies:
        body.moved(frame)
        local = [f32(f32(value(x)-(value(body.offset) if axis==1 else 0))*10) for axis,x in enumerate(target)]
        if remove_cells(body.boxes,local)[1]:
            hits.append((body,local))
    require(len(hits)==1,'history target does not identify one removable owner')
    return hits[0]


def _cut(bodies, source, local, frame):
    remain, removed = remove_cells(source.boxes,local)
    require(removed,'required history cut removed no unprotected material')
    parts = components(remain)
    require(parts,'required history cut erased owner')
    created=[]
    next_ident = max(b.ident for b in bodies)+1
    for boxes in parts:
        anchored=any(box.material==1 for box in boxes)
        bottom=min(box.lo[1] for box in boxes)
        created.append(Body(next_ident,boxes,anchored,None if anchored else frame,
                            source.offset,source.speed,bottom,source.offset,source.speed))
        next_ident+=1
    bodies[:]=[b for b in bodies if b is not source]+created
    return removed,created


def schedule(config):
    require((config['warmup'],config['frames']) == ('120','3600'), 'history requires the complete 120/3600 schedule')
    schedule_id=config.get('schedule','history-v1')
    counts={'history-v1':120,'history-v2':120,'history-12-v1':12,'history-48-v1':48,
            'fill-history-v1':120,'body-rich-history-v1':120}
    require(schedule_id in counts and
            (schedule_id.startswith('fill-') if config.get('control')=='fill' else
             schedule_id.startswith('body-rich-') if config.get('control')=='body-rich' else
             schedule_id in ('history-v1','history-v2','history-12-v1','history-48-v1')) and
            (schedule_id=='history-v2' if config['preset'] not in ('small','large') else schedule_id!='history-v2'),
            'unsupported history schedule')
    count=counts[schedule_id]
    cut_frames=CUT_FRAMES[:count]
    key=tuple(config.get(name) for name in ('preset','seed','side_m','warmup','frames','fragment_budget','control','schedule'))
    if key in _SCHEDULE_CACHE:
        return _SCHEDULE_CACHE[key]
    owners=generate(config['preset'],int(config['seed']),config.get('control'))
    bodies=[Body(i,o.boxes,True) for i,o in enumerate(owners,1)]
    opening=camera(*pose('opening',0,config['preset'],int(config['seed']),'traversal-v2',config.get('control')))
    actions=[];views=[];removed_total=0
    for k,frame in enumerate(CUT_FRAMES):
        n,r,a,v,local,target=_target(k,config)
        view,eye=_view(a,n,r,v,local,target,config)
        source,location=_source(bodies,target,frame)
        # Check the declared pre-edit view against actual evolving occupancy.
        ray=ray_to(eye,list(map(value,target)))
        hit=exact_pick([(b.ident,box,value(b.offset)) for b in bodies for box in b.boxes],
                       eye,list(map(value,ray['direction'])))
        require(hit['owner']==str(source.ident) and hit['distance']<256,
                'history pre-edit owner unreachable at action '+str(k))
        removed,created=_cut(bodies,source,location,frame)
        removed_total+=len(removed)
        require(len(bodies)<=int(config['fragment_budget'])+len(owners),'history fragment budget admission')
        actions.append({'action':str(k),'frame':str(frame),'measured_ordinal':str(frame-121),
                        'target_m':target,'radius_m':bits(.2),'required':True,
                        'expected_removed_cells':str(len(removed)),
                        'expected_owner_role':owners[source.ident-1].role if source.ident<=len(owners) else None,
                        'reference_removed_cells':[[*map(str,p),str(m)] for p,m in sorted(removed.items())],
                        'pre_edit_ray':ray,'pre_edit_hit':{key:str(val) for key,val in hit.items() if key!='point'},
                        'reference_components':str(len(created))})
        views.append(view)
    if not config.get('control'):
        if config['preset'] in ('small','large'):
            require(removed_total==(2440 if config['preset']=='small' else 2472),
                    'history source removal total differs from accepted recipe')
    far_eye,far_look=pose('far',None,config['preset'],int(config['seed']),'traversal-v2',config.get('control'))
    far=camera(far_eye,far_look)
    # Resolve the entire baseline route before shortening the action list.
    # Later camera visits remain byte-identical to the full history.
    frames=[]
    last=views[-1]
    for i in range(3721):
        ordinal=i-121
        if i<=120: view=opening
        elif ordinal<=1439: view=views[min(ordinal//12,119)]
        elif ordinal<=1559:
            t=(ordinal-1439)/120
            eye=[f32(value(x)+(y-value(x))*t) for x,y in zip(last['eye_m'],far_eye)]
            # Interpolate the previous view's declared target, not its yaw/pitch.
            final_target=list(map(value,actions[-1]['target_m']))
            look=[f32(x+(y-x)*t) for x,y in zip(final_target,far_look)]
            view=camera(eye,look)
        else: view=far
        frames.append({'frame':str(i),'phase':'startup' if i==0 else 'warmup' if i<=120 else 'edit' if i in cut_frames else 'ordinary',
                       'measured_ordinal':str(ordinal) if i>120 else None,'camera':view,'picking':False,
                       'actions':[str(ordinal//12)] if i in cut_frames else []})
    actions=actions[:count]
    points=[{'name':'initialization','frame':'0'},{'name':'review_opening','frame':'0'},{'name':'warmup_end','frame':'120'}]
    points += [{'name':'action_'+str(k),'frame':str(frame)} for k,frame in enumerate(cut_frames)]
    points += [{'name':'after_cut_'+str(n),'frame':str(frame)} for n,frame in NAMED if n<=count]
    points += [{'name':'history_overview','frame':'1681'},{'name':'completion','frame':'3720'}]
    review=[{'name':'opening','frame':'0','features':['district and structures']}]
    review += [{'name':'cut_'+str(k),'frame':str(frame),
                'features':['remaining back wall','new exposed back-wall surfaces']
                    if config.get('control')=='body-rich' and k%10==6 else
                    ['removed material','new exposed surfaces']} for k,frame in enumerate(cut_frames)]
    review += [{'name':'uncut_visit_'+str(k),'frame':str(frame),
                'features':['no new cut at this camera visit','remaining material at later target']}
               for k,frame in enumerate(CUT_FRAMES) if k>=count]
    review += [{'name':'history_overview','frame':'1681','features':['cumulative destruction','remaining anchored material']
                if count==120 else [f'destruction after {count} cuts','remaining uncut later targets']},
               {'name':'completion','frame':'3720','features':['retained geometry','settled fragments']
                if count==120 else [f'retained geometry after {count} cuts','settled fragments','remaining uncut later targets']}]
    populations={'cuts_1_12':['0','143']}
    if count>=48: populations['cuts_13_48']=['144','575']
    if count==120: populations['cuts_49_120']=['576','1439']
    if count<120: populations['post_prefix']=[str(count*12),'1439']
    populations.update(overview=['1440','1559'],tail=['1560','3599'])
    frozen={'schema':SCHEMA,'record_type':'schedule','schedule_id':schedule_id,'fixed_step':'0x3c888889',
            'warmup_frames':'120','measured_frames':'3600','opening':opening,'frames':frames,'actions':actions,
            'review_views':review,'required_checkpoints':points,'checkpoint_implementation':'megascene-checkpoint/1',
            'update_order':['physics','edit','view_picking_disabled','render'],
            'history_populations':populations}
    if schedule_id == 'history-v2':
        frozen['history_neighborhood_mapping']={'version':'coprime-prior-visits-v1',
            'stride':str(history_stride(side_count(config['preset'])**2)),
            'group_visits':[{'group':str(b),'neighborhood':str(history_visit(b,side_count(config['preset'])**2,int(config['seed']))[0]),
                             'prior_visits':str(history_visit(b,side_count(config['preset'])**2,int(config['seed']))[1])}
                            for b in range(12)]}
    if count<120:
        frozen['variant']={'baseline_schedule_id':'history-v1','required_actions':str(count),
                           'omitted_actions':{'first':str(count),'last':'119','count':str(120-count)},
                           'omitted_action_disposition':'not_required_for_variant',
                           'camera_track':'full_history_v1_all_3600_measured_frames',
                           'baseline_completion_equivalence':False}
    if config.get('control') == 'body-rich':
        eye,look=pose('interior',0,config['preset'],int(config['seed']),'traversal-v2','body-rich')
        ray=ray_to(eye,look)
        hit=exact_pick([(i,box,0.) for i,owner in enumerate(owners,1) for box in owner.boxes],
                       eye,list(map(value,ray['direction'])))
        require((hit['owner'],hit['material'],hit['kind'])==('2','5','1') and hit['distance']<256,
                'body-rich interior view misses the remaining removable back wall')
        frozen['diagnostic_views']=[{'name':'interior_remaining_wall','camera':camera(eye,look),
                                     'eye_m':list(map(bits,eye)),'look_m':list(map(bits,look)),
                                     'expected_owner':'2','expected_material':'5','reference_hit':hit}]
    _SCHEDULE_CACHE[key]=frozen
    return frozen


def audit_actions(records, frozen):
    result=_audit_actions(records,frozen)
    require(result['actions']==str(len(frozen['actions'])) and int(result['removed_cells'])==
            sum(int(a['expected_removed_cells']) for a in frozen['actions']),
            'incomplete irregular history')
    return result


def _shape(boxes):
    return {'anchored':any(b.material==1 for b in boxes),
            'occupancy':strings(occupancy(boxes)), 'surface':surface(surface_reference(boxes))}


def _cells(boxes, material=None):
    return sum(math.prod(hi-lo for lo,hi in zip(box.lo,box.hi)) for box in boxes
               if material is None or box.material==material)


class Reference:
    """Independent sparse components and motion, mapped to actual lifetime IDs."""
    def __init__(self, initial, frozen):
        self.frozen=frozen
        self.phases=[initial]
        self.bodies=[[Body(int(b['id']),boxes_of(b),b['anchored']) for b in initial['bodies']]]
        self.releases={}
        self.moved_targets=[]

    def at(self, frame):
        phase=min(sum(int(a['frame'])<=frame for a in self.frozen['actions']),len(self.phases)-1)
        base=self.phases[phase]
        body_values=[]
        for body in sorted(self.bodies[phase],key=lambda b:b.ident):
            item=next(b for b in base['bodies'] if b['id']==str(body.ident))
            if body.release is not None:
                offset,speed=motion(frame-body.release,body.bottom,value(body.start_offset),value(body.start_speed))
                item={**item,'offset_m':offset,'velocity_m_s':speed}
            body_values.append(item)
        return {**base,'bodies':body_values,'view':{**base['view'],**self.frozen['frames'][frame]['camera']}}

    def cut(self, action, actual):
        frame=int(action['frame'])
        before=self.at(frame)
        current=[copy(b) for b in self.bodies[-1]]
        source,local=_source(current,action['target_m'],frame)
        within=int(action['action'])%10
        if within==5:
            release=self.releases[int(action['action'])//10]
            require(source.ident==int(release['body_id']) and not source.anchored and
                    value(source.offset)<0 and value(source.speed)<0 and frame-int(release['frame'])==12,
                    'history moving-beam target missed its released span')
            self.moved_targets.append({'action':action['action'],'body_id':str(source.ident),
                                       'frame':str(frame),'offset_m':source.offset,'velocity_m_s':source.speed})
        if within in (8,9):
            require(source.anchored, 'history bridge target did not hit an anchored stub')
        source_state=next(b for b in before['bodies'] if b['id']==str(source.ident))
        ray=action['pre_edit_ray']
        hit=exact_pick([(body.ident,box,value(body.offset)) for body in current
                        for box in body.boxes],list(map(value,ray['origin_m'])),list(map(value,ray['direction'])))
        require(hit['owner']==str(source.ident) and hit['distance']<256,
                'evolving pre-edit owner unreachable at action '+action['action'])
        keep,removed=remove_cells(source.boxes,local)
        require([[*map(str,p),str(m)] for p,m in sorted(removed.items())]==action['reference_removed_cells'],
                'history revisit/moved target removed different material at action '+action['action'])
        parts=components(keep)
        first=int(before['next_id'])
        fresh=[b for b in actual['bodies'] if int(b['id'])>=first]
        require({int(b['id']) for b in fresh}==set(range(first,first+len(parts))),
                'history lifetime ID allocation mismatch at action '+action['action'])
        made=[];new_bodies=[]
        for boxes in parts:
            shape=_shape(boxes)
            matches=[b for b in fresh if b['occupancy']==shape['occupancy']]
            require(len(matches)==1,'history component occupancy/ownership mismatch at action '+action['action'])
            ident=matches[0]['id']
            made.append({**shape,'id':ident,'revision':'0',
                         'offset_m':source_state['offset_m'],'velocity_m_s':source_state['velocity_m_s']})
            new_bodies.append(Body(int(ident),boxes,shape['anchored'],None if shape['anchored'] else frame,
                                   source_state['offset_m'],source_state['velocity_m_s'],
                                   min(box.lo[1] for box in boxes),source_state['offset_m'],source_state['velocity_m_s']))
        outcome={k:action[k] for k in ('action','frame','target_m')} | {
            'accepted':True,'outcome':'accepted','removed_cells':action['expected_removed_cells']}
        state={**before,'bodies':sorted([b for b in before['bodies'] if b['id']!=source_state['id']]+made,key=lambda b:int(b['id'])),
               'cells':str(int(before['cells'])-len(removed)),'removed':str(len(removed)),'status':'1',
               'next_id':str(first+len(parts)),
               'fragments':str(sum(not b['anchored'] for b in before['bodies'] if b['id']!=source_state['id'])+
                               sum(not b['anchored'] for b in made)),
               'action_outcomes':before['action_outcomes']+[outcome]}
        self.phases.append(state)
        self.bodies.append([b for b in self.bodies[-1] if b.ident!=source.ident]+new_bodies)
        if within==4:
            released=[b for b in new_bodies if not b.anchored]
            require(len(released)==1 and released[0].bottom==42+(8 if self.frozen.get('schedule_id')=='fill-history-v1' else 0),
                    'history support cut did not release the declared span')
            self.releases[int(action['action'])//10]={'body_id':str(released[0].ident),'frame':str(frame)}
        diff=mismatch(state,actual)
        require(diff is None,'history intermediate state mismatch at action '+action['action']+': '+str(diff))
        return source_state,parts


def audit(records,frozen,initial,initial_work,complete,thorough=False):
    failures=[];catalog=[];checked=set();phase_work=[];moving_windows=[]
    try:
        require(complete,'complete declared history schedule unavailable')
        audit_actions(records,frozen)
        ref=Reference(initial,frozen)
        checks=[r for r in records if r['record_type'] in ('checkpoint','static_audit')]
        by_frame={r['frame']:r for r in checks}
        require(len(by_frame)==len(checks),'duplicate history checkpoint frame')
        previous_work=initial_work
        cut_frames={int(a['frame']) for a in frozen['actions']}
        for action in frozen['actions']:
            cp=by_frame[action['frame']]
            before,parts=ref.cut(action,cp['payload'])
            after=ref.phases[-1]
            work=cp['work']
            shared={b['id'] for b in ref.phases[-2]['bodies']} & {b['id'] for b in after['bodies']}
            require([w for w in work if w['id'] in shared]==[w for w in previous_work if w['id'] in shared],
                    'unaffected history representation changed')
            require({w['id'] for w in work}=={b['id'] for b in after['bodies']} and len(work)==len(after['bodies']),
                    'history work inventory missing/duplicate')
            for b in after['bodies']:
                boxes=boxes_of(b);w=next(w for w in work if w['id']==b['id'])
                require(w['cells']==str(_cells(boxes)) and w['protected_cells']==str(_cells(boxes,1)),
                        'history work/material inventory mismatch at action '+action['action'])
            phase_work.append(work);previous_work=work
        points={p['name']:p['frame'] for p in frozen['required_checkpoints']}
        seen=set();cache={}
        def expected_at(i):
            # Bodies have settled by here; the camera keeps interpolating
            # until absolute frame 1681, so the whole payload stabilizes then.
            key=min(i,1681)
            if key not in cache:
                state=ref.at(key)
                cache[key]=(state,digest(state),{b['id']:digest(b) for b in state['bodies']})
            return cache[key]
        for row in checks:
            frame=row['frame'];i=int(frame)
            require(frame not in checked,'duplicate history checkpoint');checked.add(frame)
            names=[name for name,at in points.items() if at==frame]
            require(row['names']==names and row['record_type']==('checkpoint' if names else 'static_audit') and
                    ('payload' in row)==bool(names),'history checkpoint names/kind/payload mismatch')
            state,sha,body_hashes=expected_at(i)
            if names:
                diff=mismatch(state,row['payload'])
                require(diff is None,'history checkpoint mismatch at frame '+frame+': '+str(diff))
                require(digest(row['payload'])==row['sha256'],'history checkpoint digest mismatch')
            require(row['sha256']==sha and row['body_sha256']==body_hashes,'history state/geometry mismatch at frame '+frame)
            phase=sum(at<=i for at in cut_frames)
            require(row['work']==([initial_work]+phase_work)[phase], 'history representation changed between edits')
            for name in names:
                require(name not in seen,'duplicate history checkpoint name');seen.add(name)
                catalog.append({'name':name,'frame':frame,'sha256':sha,'body_sha256':body_hashes})
        require(seen==set(points),'missing history edit/named checkpoint')
        require(checked==({f['frame'] for f in frozen['frames']} if thorough else set(points.values())),
                'incomplete history checkpoint replay')
        native=[r for r in records if r['record_type']=='native_audit']
        renders=[r for r in records if r['record_type']=='render_work']
        frames=[r for r in records if r['record_type']=='frame']
        require(len(native)==len(renders)==len(frames)==3721,'incomplete history native replay')
        observed=motion_records(records);expected_motion={}
        for group,release in sorted(ref.releases.items()):
            samples=[]
            for frame in range(int(release['frame'])+1,int(release['frame'])+12):
                body=next(b for b in ref.at(frame)['bodies'] if b['id']==release['body_id'])
                require(not body['anchored'] and value(body['offset_m'])<0 and value(body['velocity_m_s'])<0 and
                        observed.get((str(frame),release['body_id']))=={k:body[k] for k in ('id','revision','offset_m','velocity_m_s')},
                        'history named moving window missing or already settled')
                samples.append({'frame':str(frame),'offset_m':body['offset_m'],'velocity_m_s':body['velocity_m_s']})
            moving_windows.append({'group':str(group),'body_id':release['body_id'],
                                   'release_frame':release['frame'],'samples':samples})
        releases=sum(int(a['action'])%10==4 for a in frozen['actions'])
        moved=sum(int(a['action'])%10==5 for a in frozen['actions'])
        require(len(moving_windows)==releases and len(ref.moved_targets)==moved,
                'history missing moved-span targets/windows')
        previous_native=None;previous_state=None
        for i,(n,w,f) in enumerate(zip(native,renders,frames)):
            require(n['frame']==w['frame']==f['frame']==str(i),'history native/frame order mismatch')
            state,_,_=expected_at(i)
            ids={b['id'] for b in state['bodies']}
            for b in state['bodies']:
                if not b['anchored']:
                    expected_motion[str(i),b['id']]={k:b[k] for k in ('id','revision','offset_m','velocity_m_s')}
            work=([initial_work]+phase_work)[sum(at<=i for at in cut_frames)]
            require(set(n['mesh_sha256'])==ids and int(n['vertices_checked'])==sum(int(b['vertices']) for b in work),
                    'history full-mesh inventory mismatch')
            require(len(n['drawn_ids'])==len(set(n['drawn_ids'])) and set(n['drawn_ids'])<=ids and
                    str(len(n['drawn_ids']))==w['main_body_draws'] and int(n['reference_visible'])<=len(n['drawn_ids']),
                    'history visible geometry mismatch')
            changed=i==0 or i in cut_frames or any(b['offset_m']!=next(old['offset_m'] for old in previous_state['bodies'] if old['id']==b['id'])
                    for b in state['bodies'] if previous_state and any(old['id']==b['id'] for old in previous_state['bodies']))
            require(w['shadow_refresh'] is changed,'history shadow invalidation mismatch')
            if previous_native:
                for ident in ids & set(previous_native['mesh_slots']):
                    require(n['mesh_slots'][ident]==previous_native['mesh_slots'][ident] and
                            n['mesh_sha256'][ident]==previous_native['mesh_sha256'][ident],
                            'history unchanged mesh slot/data changed')
                if i not in cut_frames:
                    require(n['proxy_cache_sha256']==previous_native['proxy_cache_sha256'] and w['proxy_rebuilt']=='0',
                            'history translation/camera invalidated proxy')
            previous_native=n;previous_state=state
        require(observed==expected_motion,'history moving-body evidence missing or incorrect')
    except (ValueError,KeyError,TypeError,StopIteration,IndexError) as exc:
        failures.append({'reason':str(exc) or 'missing required history evidence'})
    return {'schema':SCHEMA,'record_type':'checkpoint_comparison','synthetic':any(r.get('synthetic',False) for r in records),
            'status':'fail' if failures else 'pass','failures':failures,'checkpoints':catalog,
            'checked_frames':str(len(checked)),'native_frames':str(sum(r['record_type']=='native_audit' for r in records)),
            'actual_work':initial_work,'edited_work':phase_work,'moving_window':moving_windows,
            'moved_targets':ref.moved_targets if 'ref' in locals() else [],
            'scope':str(len(frozen['actions']))+' evolving cuts, intermediate ownership/material/surface/motion and native cache replay'}
