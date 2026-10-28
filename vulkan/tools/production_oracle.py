#!/usr/bin/env python3
import json
import math
from pathlib import Path
import struct

import numpy as np
from PIL import Image

import reference_lighting as ref
import shadow_causality as causal

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT/'build/milestone-6-production'
TOLERANCES = dict(display_byte_absolute=1, production_depth_absolute=3e-7,
                  gpu_ray_operation_ulp_budget=12, ring_edge_pixels=.03,
                  ring_depth_absolute=6e-8)


def load(name):
    raw = (BUILD/(name+'.uniform')).read_bytes()
    words = np.frombuffer(raw, '<u4')
    values = np.frombuffer(raw, '<f4')
    w, h = map(int, values[48:50])
    return dict(name=name, w=w, h=h, words=words, values=values,
                color=np.frombuffer((BUILD/(name+'.rgba')).read_bytes(), np.uint8).reshape(h,w,4),
                depth=np.frombuffer((BUILD/(name+'.depth')).read_bytes(), '<f4').reshape(h,w),
                shadow=np.frombuffer((BUILD/(name+'.shadow')).read_bytes(), '<f4').reshape(512,512))


def rgba(name, w, h):
    return np.frombuffer((BUILD/(name+'.rgba')).read_bytes(), np.uint8).reshape(h,w,4)


def rays(frame):
    v=frame['values']; w,h=frame['w'],frame['h']
    y,x=np.mgrid[:h,:w].astype(np.float32)
    ox=(x+.5-np.float32(w*.5))/v[47]
    oy=(np.float32(h*.5)-y-.5)/v[47]
    return v[44:47]+(ox[:,:,None]*v[36:39]+oy[:,:,None]*v[40:43])


def exact_cells(cells, direction, mask, fields):
    u,v,ax,ay,az,width,height,_=[np.where(mask,value,1 if i in (5,6,7) else 0) for i,value in enumerate(fields)]
    anchor=np.stack((ax,ay,az),axis=2).astype(np.uint32)
    du=np.clip(np.floor(np.float32(u)*np.float32(width)),0,width-1).astype(np.uint32)
    dv=np.clip(np.floor(np.float32(v)*np.float32(height)),0,height-1).astype(np.uint32)
    expected=anchor.copy()
    xface=direction<2; yface=(direction>=2)&(direction<4); zface=direction>=4
    expected[:,:,0]+=np.where(yface|zface,du,0).astype(np.uint32)
    expected[:,:,1]+=np.where(xface,du,np.where(zface,dv,0)).astype(np.uint32)
    expected[:,:,2]+=np.where(xface|yface,dv,0).astype(np.uint32)
    assert np.array_equal(cells[mask],expected[mask]), 'Exact independent normalized F32 expansion/clamp tangential cell ownership'
    return expected


def metadata(frame):
    return [np.frombuffer((BUILD/(frame['name']+f'-metadata-{i}.rgba')).read_bytes(),'<f4').reshape(frame['h'],frame['w']) for i in range(8)]


def identities(frame):
    name,w,h=frame['name'],frame['w'],frame['h']
    material=rgba(name+'-mode2',w,h).copy().view('<u4').reshape(h,w)
    direction=rgba(name+'-mode3',w,h)[:,:,0]
    cells=np.stack([rgba(name+f'-mode{i}',w,h).copy().view('<u4').reshape(h,w) for i in (4,5,6)],axis=2)
    raw_depth=np.frombuffer((BUILD/(name+'-mode2.depth')).read_bytes(),'<f4').reshape(h,w)
    assert np.array_equal(frame['depth'],raw_depth), (name,'Shaded coverage/depth must match independent raw material path at every pixel')
    mask=raw_depth<1
    assert np.isfinite(frame['depth']).all() and ((frame['depth']>=0)&(frame['depth']<=1)).all()
    assert np.isfinite(frame['shadow']).all() and ((frame['shadow']>=0)&(frame['shadow']<=1)).all()
    assert (direction[mask]<6).all()
    direction=np.where(mask,direction,0)
    body=json.loads((BUILD/(name+'.body.json')).read_text())
    owned=np.zeros((h,w),dtype=np.uint32)
    neighbor=np.zeros((h,w),dtype=np.uint32)
    normals=np.asarray(ref.NORMALS,dtype=np.int32)[direction]
    adjacent=cells.astype(np.int64)+normals
    if 'boxes' in body and body['boxes']:
        high=np.max(np.asarray(body['boxes'])[:,3:6],axis=0)
        occupancy=np.zeros(tuple(high[::-1]),dtype=np.uint32)
        for b in body['boxes']:
            x,y,z,hx,hy,hz,m=b
            assert not occupancy[z:hz,y:hy,x:hx].any()
            occupancy[z:hz,y:hy,x:hx]=m
    elif 'cells' in body:
        side=body['side']; high=np.asarray([side]*3)
        occupancy=np.asarray(body['cells'],dtype=np.uint32).reshape(side,side,side)
    else:
        high=np.asarray([1,1,1]); occupancy=np.zeros((1,1,1),np.uint32)
    valid=mask&np.all(cells<high,axis=2)
    c=cells[valid]; owned[valid]=occupancy[c[:,2],c[:,1],c[:,0]]
    valid=mask&np.all((adjacent>=0)&(adjacent<high),axis=2)
    c=adjacent[valid]; neighbor[valid]=occupancy[c[:,2],c[:,1],c[:,0]]
    assert np.array_equal(owned[mask],material[mask]), (name,'exact original material/cell mismatch')
    assert not np.any(neighbor[mask]), (name,'rendered internal face identity')
    assert (frame['color'][:,:,3]==255).all()
    fields=[np.where(mask,value,1 if i in (5,6,7) else 0) for i,value in enumerate(metadata(frame))]
    exact_cells(cells,direction,mask,fields)
    ray=rays(frame); eye=frame['values'][32:35]
    axis=direction//2
    plane=np.take_along_axis(cells,axis[:,:,None],axis=2)[:,:,0].astype(np.float32)+(direction%2)
    distance=(plane-np.take(eye,axis))/np.take_along_axis(ray,axis[:,:,None],axis=2)[:,:,0]
    points=eye+distance[:,:,None]*ray
    anchors=np.stack(fields[2:5],axis=2)
    axes_u=np.where(direction<2,1,0); axes_v=np.where(direction<4,2,1)
    origin_u=np.take_along_axis(anchors,axes_u[:,:,None],axis=2)[:,:,0]
    origin_v=np.take_along_axis(anchors,axes_v[:,:,None],axis=2)[:,:,0]
    pu=np.take_along_axis(points,axes_u[:,:,None],axis=2)[:,:,0]-origin_u
    pv=np.take_along_axis(points,axes_v[:,:,None],axis=2)[:,:,0]-origin_v
    y,x=np.mgrid[:h,:w].astype(np.float32)
    horizontal=(x+.5-np.float32(w*.5))[:,:,None]/frame['values'][47]*frame['values'][36:39]
    vertical=(np.float32(h*.5)-y-.5)[:,:,None]/frame['values'][47]*frame['values'][40:43]
    eps=np.finfo(np.float32).eps
    ray_error=TOLERANCES["gpu_ray_operation_ulp_budget"]*eps*(np.abs(frame['values'][44:47])+np.abs(horizontal)+np.abs(vertical))
    normal_ray=np.take_along_axis(ray,axis[:,:,None],axis=2)[:,:,0].astype(float)
    normal_error=np.take_along_axis(ray_error,axis[:,:,None],axis=2)[:,:,0]
    time_error=np.abs(distance)*normal_error/np.maximum(np.abs(normal_ray)-normal_error,1e-30)+2*np.spacing(np.abs(distance))
    world_error=np.abs(ray)*time_error[:,:,None]+np.abs(distance)[:,:,None]*ray_error+8*eps*(np.abs(eye)+np.abs(points)+np.abs(anchors))
    for actual,index,extent_index,tangent in ((pu,0,5,axes_u),(pv,1,6,axes_v)):
        bound=np.take_along_axis(world_error,tangent[:,:,None],axis=2)[:,:,0]+4*eps*(np.abs(fields[index]*fields[extent_index])+1)
        assert np.all(np.abs(actual-fields[index]*fields[extent_index])[mask]<=bound[mask]), 'Independent camera ray/plane enclosure for actual normalized GPU inputs'
    expected_depth=1-frame['values'][35]/distance
    errors=np.abs(expected_depth-frame['depth'])
    assert np.max(errors[mask],initial=0)<3e-6, (name,'camera depth/plane identity')
    if name in ('intact','reset','srgb'):
        for x,y,m,cell in ((265,179,4,[226,211,76]),(449,190,3,[337,226,72]),(448,194,3,[335,217,72]),(468,208,3,[347,214,64])):
            assert int(material[y,x])==m, (name,'literal front material at reproduced raster fringe',x,y)
            assert cells[y,x].tolist()==cell, (name,'literal owning cell at reproduced raster fringe',x,y)
        assert int(direction[179,265])==5
        assert cells[179,265].tolist()==[226,211,76], 'Literal production-vertex raster boundary must clamp the -3.0517578125e-5 local V to its owning cell'
    return body,material,direction,cells,mask,points


def pcf(frame, point, normal):
    v=frame['values']
    return ref.production_pcf(v[16:32].tolist(),float(v[81]),float(v[82]),float(v[83]),
                              tuple(map(float,point)),tuple(map(float,normal)),512,
                              lambda x,y:float(frame['shadow'][y,x]))


def rgb(base, normal, count):
    return np.asarray([round(min(1,max(0,c))*255) for c in ref.display_rgb(ref.daylight(base,normal,count))])


def lighting(frame, material, direction, mask, points):
    positions=np.argwhere(mask)
    sampled=positions[::max(1,len(positions)//2400)]
    known=stable=ambiguous=unknown=0; counts={}; wrong_units=0; maximum_error=0
    witnesses=[]
    for y,x in sampled:
        m=int(material[y,x]); d=int(direction[y,x]); normal=ref.NORMALS[d]
        if m not in range(1,6):
            assert frame['color'][y,x,:3].tolist()==[255,0,255], 'Unknown occupied material must remain unlit magenta'
            unknown+=1
            continue
        answer=pcf(frame,points[y,x],normal)
        count=answer['visible_count']; interval=answer.get('count_interval',[count,count])
        allowed=range(interval[0],interval[1]+1)
        base=frame['values'][60+4*(m-1):63+4*(m-1)]
        expected=[rgb(base,normal,n) for n in allowed]
        actual=frame['color'][y,x,:3].astype(int)
        error=min(int(np.max(np.abs(actual-color))) for color in expected)
        assert error<=1, (frame['name'],int(x),int(y),m,d,count,interval,actual.tolist(),[c.tolist() for c in expected],answer)
        maximum_error=max(maximum_error,error); known+=1
        ambiguous+=bool(answer.get('ambiguous_tap_indices'))
        stable+=not bool(answer.get('ambiguous_tap_indices'))
        counts[count]=counts.get(count,0)+1
        v=frame['values']
        wrong=ref.production_pcf(v[16:32].tolist(),float(v[81]),float(v[82]),float(v[83]),tuple(map(float,points[y,x])),normal,512,lambda tx,ty:float(frame['shadow'][ty,tx]),lose_z_scale=True)
        wrong_units+=wrong['visible_count']!=count
        if len(witnesses)<16 and 0<count<9:
            witnesses.append(dict(name=f'{frame["name"]}-{int(x)}-{int(y)}',provenance='gpu_world_receiver',
                                  point_bits=[ref.bits(float(a)) for a in points[y,x]], normal_bits=[ref.bits(a) for a in normal],
                                  material=m,observed_rgb=actual.tolist(),predicted_visibility=count))
    assert known>100 or not np.any(mask)
    return dict(sampled_world_rgb=known,unlit_unknown_samples=unknown,stable_pcf=stable,ambiguous_shadow_taps=ambiguous,
                visibility_histogram=counts,max_display_byte_error=maximum_error,
                missing_z_scale_negative_control_differences=wrong_units),witnesses


def backdrop(frame, mask):
    v=frame['values']; eye=v[32:35]; ray=rays(frame)
    y,x=np.mgrid[:frame['h'],:frame['w']]
    canonical=np.floor((y.astype(np.float32)+.5)*np.float32(512)/np.float32(frame['h'])).astype(int)
    packed=1054752+(np.minimum(canonical,511)//32)*65793
    expected=np.stack([(packed>>16)&255,(packed>>8)&255,packed&255],axis=2)
    visible=~mask
    ground=np.zeros_like(visible)
    if eye[2]>-.5:
        t=(-.5-eye[2])/np.where(ray[:,:,2]!=0,ray[:,:,2],np.float32(1e-30))
        point=eye+t[:,:,None]*ray
        ground=(ray[:,:,2]<0)&np.all((point[:,:,:2]>=-16)&(point[:,:,:2]<=24),axis=2)&visible
        for gy,gx in np.argwhere(ground)[::max(1,int(ground.sum())//300)]:
            p=point[gy,gx]; fraction=np.mod(p[:2]*.5,1)
            grid=np.any((fraction<.0125)|(fraction>.9875))
            base=(.055,.065,.08) if grid else (.10,.12,.15)
            a=pcf(frame,p,(0,0,1)); count=a['visible_count']
            assert np.max(np.abs(frame['color'][gy,gx,:3].astype(int)-rgb(base,(0,0,1),count)))<=1
    background=visible&~ground
    assert np.array_equal(frame['color'][:,:,:3][background],expected[background]), (frame['name'],'pixel-center gradient')
    assert np.all(frame['depth'][ground]==1), 'Ground must not write voxel depth'
    return dict(exact_gradient_pixels=int(background.sum()),ground_pixels=int(ground.sum()))


def selection(frame, cells, mask):
    name=frame['name']; selected=load(name+'-selected')
    assert np.array_equal(frame['depth'],selected['depth'])
    count=int(selected['words'][59]); slots=selected['words'][84:584].reshape(125,4)
    assert count<=125 and not slots[count:].any() and not slots[:,3].any()
    inside=np.zeros_like(mask)
    for c in slots[:count,:3]:
        inside|=np.all(cells==c,axis=2)&mask
    diagnostic=rgba(name+'-selected-id',frame['w'],frame['h'])
    assert np.array_equal(diagnostic[:,:,0][mask],inside[mask].astype(np.uint8)*255)
    assert np.all(selected['color'][inside,:3]==(255,255,0))
    assert np.array_equal(frame['color'][~inside],selected['color'][~inside]), 'Exact replacement must affect selected occupied identities only'
    return dict(selected_cell_slots=count,exact_selected_pixels=int(inside.sum()))


def check_ring_visibility(observed, definite, possible, indistinguishable, name):
    errors=((definite&~observed)|(observed&~possible))&~indistinguishable
    assert not errors.any(), (name,'ring raster/depth mismatch',int(errors.sum()),np.argwhere(errors)[:12].tolist())


def rings(frame):
    before=load(frame['name']+'-selected'); after=load(frame['name']+'-rings')
    assert np.array_equal(before['depth'],after['depth']), 'Ring depth writes must be disabled'
    assert np.array_equal(before['shadow'],after['shadow'])
    v=after['values']; eye=v[32:35].astype(float); center=v[52:55].astype(float)/10; radius=float(v[55])/10
    right,up,forward=(v[i:i+3].astype(float) for i in (36,40,44))
    near=float(v[35]); focal=float(v[47]); w,h=frame['w'],frame['h']
    support=np.zeros((h,w),bool); visible=np.zeros_like(support); edge=np.zeros_like(support); contact=np.zeros_like(support)
    definite=np.zeros_like(support); possible=np.zeros_like(support)
    clipped=degenerate=occluded_segment_pixels=0; minimum_squared=math.inf
    linear_visible=np.zeros_like(support)
    for ring in range(3):
        for segment in range(32):
            def endpoint(index):
                angle=index*.1963495408; c,s=radius*math.cos(angle),radius*math.sin(angle)
                delta=((c,s,0),(c,0,s),(0,c,s))[ring]
                d=center+delta-eye
                return np.asarray([np.dot(d,right),np.dot(d,up),np.dot(d,forward)])
            a,b=endpoint(segment),endpoint(segment+1)
            if max(a[2],b[2])<near: continue
            if min(a[2],b[2])<near:
                low,high=(a,b) if a[2]<b[2] else (b,a)
                cut=low+(near-low[2])/(high[2]-low[2])*(high-low); cut[2]=near
                if a[2]<near: a=cut
                else: b=cut
                clipped+=1
            p=np.asarray([w/2+focal*a[0]/a[2],h/2-focal*a[1]/a[2]])
            q=np.asarray([w/2+focal*b[0]/b[2],h/2-focal*b[1]/b[2]])
            delta=q-p; squared=float(np.dot(delta,delta)); minimum_squared=min(minimum_squared,squared)
            degenerate+=squared<1e-6
            lo=np.maximum(0,np.floor(np.minimum(p,q)-1).astype(int)); hi=np.minimum((w,h),np.ceil(np.maximum(p,q)+1).astype(int))
            if np.any(lo>=hi): continue
            yy,xx=np.mgrid[lo[1]:hi[1],lo[0]:hi[0]]
            t=np.clip(((xx+.5-p[0])*delta[0]+(yy+.5-p[1])*delta[1])/squared,0,1) if squared>0 else np.zeros_like(xx,float)
            distance=np.hypot(xx+.5-p[0]-t*delta[0],yy+.5-p[1]-t*delta[1])
            stroke=distance<=.75
            z=1/(1/a[2]+t*(1/b[2]-1/a[2]))
            depth=1-near/np.maximum(near,z-.0001)
            voxel=before['depth'][lo[1]:hi[1],lo[0]:hi[0]]
            key=np.s_[lo[1]:hi[1],lo[0]:hi[0]]
            support[key]|=stroke
            visible[key]|=stroke&(depth<=voxel)
            occluded_segment_pixels+=int(np.count_nonzero(stroke&(depth>voxel)))
            linear_depth=1-near/np.maximum(near,a[2]+t*(b[2]-a[2])-.0001)
            linear_visible[key]|=stroke&(linear_depth<=voxel)
            definite[key]|=(distance<.75-TOLERANCES["ring_edge_pixels"])&(depth<voxel-TOLERANCES["ring_depth_absolute"])
            possible[key]|=(distance<=.75+TOLERANCES["ring_edge_pixels"])&(depth<=voxel+TOLERANCES["ring_depth_absolute"])
            edge[key]|=np.abs(distance-.75)<=TOLERANCES['ring_edge_pixels']
            contact[key]|=stroke&(np.abs(depth-voxel)<=TOLERANCES['ring_depth_absolute'])
    observed=np.any(after['color']!=before['color'],axis=2)
    indistinguishable=np.all(before['color'][:,:,:3]==(255,255,0),axis=2)
    check_ring_visibility(observed,definite,possible,indistinguishable,frame['name'])
    assert np.all(after['color'][observed,:3]==(255,255,0))
    assert not np.any(observed&~possible), 'Ring leak through foreground voxel'
    witness=definite&~indistinguishable
    if frame['name']=='intact':
        assert witness.any(), 'Actual Atelier needs a definite observable ring witness'
        rejected=False
        try:check_ring_visibility(np.zeros_like(observed),definite,possible,indistinguishable,frame['name'])
        except AssertionError:rejected=True
        assert rejected, 'Missing-rings negative control must fail the actual visibility gate'
    return dict(definite_observable_pixels=int(witness.sum()),visible_stroke_pixels=int(visible.sum()),occluded_stroke_pixels=int((support&~visible).sum()),
                changed_pixels=int(observed.sum()),edge_band_pixels=int(edge.sum()),depth_contact_pixels=int(contact.sum()),
                near_clipped_segments=clipped,degenerate_projected_segments=degenerate,
                occluded_segment_pixels=occluded_segment_pixels,linear_eye_depth_negative_control_pixels=int(np.count_nonzero(linear_visible!=visible)),
                minimum_projected_length_squared=minimum_squared)


def raster_trace():
    output=[]
    literals=((265,179,4,[222,211,76],[6,1],[226,211,76]),
              (449,190,3,[333,226,72],[25,1],[337,226,72]),
              (448,194,3,[334,217,72],[2,1],[335,217,72]),
              (468,208,3,[347,214,64],[4,1],[347,214,64]))
    fields=[np.frombuffer((BUILD/f'intact-metadata-{i}.rgba').read_bytes(),'<f4').reshape(512,512) for i in range(8)]
    for x,y,material,anchor,extent,cell in literals:
        actual=[float(f[y,x]) for f in fields]
        assert actual[2:5]==anchor and actual[5:7]==extent, 'Actual production vertex flat rectangle metadata'
        assert not (0<=actual[0]<=1 and 0<=actual[1]<=1), 'Counterexample must remain outside analytic rectangle bounds under actual F32 arithmetic'
        output.append(dict(pixel=[x,y],front_material=material,owning_cell=cell,anchor=anchor,extent=extent,
                           u=actual[0],v=actual[1],t=actual[7],stage='metadata fixture with canonical production world vertex'))
    (BUILD/'raster-trace.json').write_text(json.dumps(output,indent=2)+'\n')
    return output


def reference_comparison():
    records=[json.loads(line) for line in (ROOT/'build/milestone-6-reference/receivers.jsonl').read_text().splitlines()]
    device=causal.read_device(BUILD/'device-precision.log')
    report={}
    for state in ('intact','carved'):
        frame=load(state)
        light=causal.LightFrame.read(BUILD/(state+'.uniform'),device['subpixel_bits'])
        boxes=json.loads((BUILD/(state+'.body.json')).read_text())['boxes']
        checked,taps,receivers=causal.evaluate_state(state,boxes,records,light,frame['shadow'])
        assert checked['pass_gate'], (state,'Independent original caster depth and changed-tap causality failed',checked)
        report[state]=dict(receivers=checked['coverage']['all_receivers'],
                           cached_reference_differs=checked['visibility']['original_cache_vs_direct_count_differences'],
                           direct_gpu_differs=checked['visibility']['original_direct_vs_gpu_count_differences'],
                           causal_gate=checked)
    return report


def main():
    report=dict(tolerances=TOLERANCES,scenes={})
    names=('intact','carved','reset','landscape','portrait','srgb','foreground','near','degenerate','palette')
    witnesses=[]
    for name in names:
        frame=load(name); body,material,direction,cells,mask,points=identities(frame)
        light,rows=lighting(frame,material,direction,mask,points); witnesses+=rows
        value=dict(exact_identity_pixels=int(mask.sum()),**light,**backdrop(frame,mask),**selection(frame,cells,mask),rings=rings(frame))
        report['scenes'][name]=value
        for suffix in ('.rgba','.depth','.shadow','.uniform'):
            assert (BUILD/(name+suffix)).read_bytes()==(BUILD/(name+'-repeat'+suffix)).read_bytes(), (name,'repeat exact attachments and frame')
        Image.fromarray(frame['color'],'RGBA').convert('RGB').save(BUILD/(name+'-plain.png'))
        Image.fromarray(load(name+'-rings')['color'],'RGBA').convert('RGB').save(BUILD/(name+'.png'))
    report['reciprocal_depth_fixture']=rings(load('reciprocal'))
    assert report['reciprocal_depth_fixture']['linear_eye_depth_negative_control_pixels']>0, 'Real ring fixture must distinguish reciprocal from linear eye depth'
    assert report['scenes']['near']['rings']['near_clipped_segments']>0
    assert report['scenes']['foreground']['rings']['occluded_stroke_pixels']>100
    for suffix in ('.rgba','.depth','.shadow','.uniform','.body.json'):
        assert (BUILD/('intact'+suffix)).read_bytes()==(BUILD/('reset'+suffix)).read_bytes(), 'exact reset state and image'
    a,b=load('intact'),load('srgb')
    assert np.max(np.abs(a['color'].astype(int)-b['color'].astype(int)))<=1, 'UNORM shader transfer versus actual SRGB attachment once-only transfer'
    reference_records=[json.loads(line) for line in (ROOT/'build/milestone-6-reference/receivers.jsonl').read_text().splitlines()]
    originals={r['state']:r['boxes'] for r in reference_records if r['kind']=='body'}
    for name in ('intact','carved','reset'):
        boxes=json.loads((BUILD/(name+'.body.json')).read_text())['boxes']
        assert boxes==[lo+hi+[m] for lo,hi,m in originals[name]], 'production state differs from original Body/Surface reference'
    report['raster_boundary_regressions']=raster_trace()
    first=load('intact'); fields=metadata(first); _,_,d,c,mask,_=identities(first)
    altered=c.copy(); altered[144,100,0]+=1
    rejected=False
    try:exact_cells(altered,d,mask,fields)
    except AssertionError:rejected=True
    assert rejected, 'Changed tangential cell [27,302,92] to [28,302,92] must fail independently of occupancy'
    report['tangential_identity_negative_control']='rejected'
    inclusive,outside=load('stroke-inclusive'),load('stroke-outside')
    assert inclusive['color'][256,260,:3].tolist()==[255,255,0], 'Inclusive actual 0.75 pixel endpoint stroke'
    assert outside['color'][256,260,:3].tolist()!=[255,255,0], 'Adjacent projected F32 outside the 0.75 pixel stroke'
    assert (inclusive['depth']==1).all() and (outside['depth']==1).all(), 'Ground and rings must leave empty voxel depth untouched'
    report['literal_stroke_pixels']=dict(inclusive_075=True,adjacent_outside_rejected=True)
    report['original_reference']=reference_comparison()
    report['once_only_output_transfer']='actual RGBA8 UNORM and SRGB within one byte'
    v=a['values']; words=a['words']
    gpu_metadata=dict(resolution=512,depth_format='D32_SFLOAT_LE',depth_origin='top_left',light_clip_bits=words[16:32].tolist(),
                  span_bits=int(words[81]),inverse_depth_bits=int(words[82]),world_bias_bits=int(words[83]),
                  receivers=[row for row in witnesses if row['name'].startswith('intact-')])
    (BUILD/'gpu-receivers.json').write_text(json.dumps(gpu_metadata,indent=2)+'\n')
    (BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':
    main()
