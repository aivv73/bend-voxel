from __future__ import annotations
import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
TOLERANCES = {'world_local_absolute': 2e-4, 'reference_f32_absolute': 1e-6,
              'palette_linear_absolute': 2e-6, 'display_byte_absolute': 1,
              'production_depth_absolute': 3e-7}
NORMALS = [(-1,0,0),(1,0,0),(0,-1,0),(0,1,0),(0,0,-1),(0,0,1)]
OKLCH = [(0.736340,0.114340,173.8965),(0.733411,0.093103,66.0436),
         (0.630974,0.062930,239.8232),(0.723628,0.119039,64.7019),(.86,.018,85)]
SUN_RAW = (-.45,.35,.82)
SUN = tuple(v/math.sqrt(sum(x*x for x in SUN_RAW)) for v in SUN_RAW)

def f32(x):
    return struct.unpack('<f',struct.pack('<f',x))[0]

def unbits(x):
    return struct.unpack('<f',struct.pack('<I',x))[0]

def bits(x):
    return struct.unpack('<I',struct.pack('<f',x))[0]

def vector(words):
    return tuple(map(unbits,words))

def dot(a,b):
    return sum(x*y for x,y in zip(a,b))

def close(a,b,tol,message):
    assert math.isfinite(a) and math.isfinite(b) and abs(a-b)<=tol, (message,a,b,tol)

def palette(material):
    light,chroma,hue=OKLCH[material-1]
    a,b=chroma*math.cos(math.radians(hue)),chroma*math.sin(math.radians(hue))
    l=(light+.3963377774*a+.2158037573*b)**3
    m=(light-.1055613458*a-.0638541728*b)**3
    s=(light-.0894841775*a-1.2914855480*b)**3
    return (4.0767416621*l-3.3077115913*m+.2309699292*s,
            -1.2684380046*l+2.6097574011*m-.3413193965*s,
            -.0041960863*l-.7034186147*m+1.7076147010*s)

def daylight(base,normal,count):
    sky=(normal[2]+1)/2
    direct=max(0,dot(normal,SUN))*count/9
    return tuple(base[i]*(ambient+sky_coefficient*sky+sun_coefficient*direct)
                 for i,(ambient,sky_coefficient,sun_coefficient) in enumerate(
                     ((.17,.23,.88),(.20,.24,.76),(.27,.21,.61))))

def display_channel(value):
    value=min(1,max(0,value))
    return 12.92*value if value<=.0031308 else 1.055*value**(1/2.4)-.055

def display_rgb(linear):
    return tuple(display_channel(x) for x in linear)

def rgb_bytes(word):
    return tuple((word>>shift)&255 for shift in (16,8,0))

def reference_layout(local,local_normal,basis,resolution):
    px,py,depth=local
    nx,ny,nz=local_normal
    scale=unbits(basis['scale'])
    n=f32(resolution)
    u=f32(f32(n*.5)+f32(f32(f32(px*scale)*n)/512))
    v=f32(f32(n*.5)-f32(f32(f32(py*scale)*n)/512))
    texel=f32(512/f32(scale*n))
    sx=f32(f32(0-f32(nx/nz))*texel)
    sy=f32(f32(ny/nz)*texel)
    return u,v,sx,sy

def reference_pcf(local,local_normal,basis,resolution,taps,direction):
    u,v,sx,sy=reference_layout(local,local_normal,basis,resolution)
    native_counts=[]
    for index,tap in enumerate(taps):
        x,y=vector(tap[:2])
        assert (x,y)==(math.floor(u)+index%3-1,math.floor(v)+index//3-1), 'tap resolution or order'
        rx=f32(f32(x+.5)-u)
        ry=f32(f32(y+.5)-v)
        receiver=f32(f32(f32(local[2]+f32(sx*rx))+f32(sy*ry))-f32(.005))
        close(receiver,unbits(tap[3]),TOLERANCES['reference_f32_absolute'],'reference world-depth receiver')
        inside=0<=x<resolution and 0<=y<resolution
        assert inside==(tap[2] is not None), 'explicit lit border'
        lit=1 if not inside else int(receiver<=unbits(tap[2]))
        assert lit==tap[4], ('actual native reference compare',tap,receiver)
        native_counts.append(lit)
    return sum(native_counts) if dot(NORMALS[direction],SUN)>0 else 9

def mul_matrix(matrix,point):
    return tuple(sum(matrix[col*4+row]*point[col] for col in range(4)) for row in range(3))

def production_pcf(matrix,span,inverse_depth,bias,point,normal,resolution,read_depth,*,lose_z_scale=False):
    """D32 world-plane oracle. Matrix words are column-major, Vulkan XY with inverted Y.

    read_depth(x,y) returns the actual normalized D32 sample at integer texels.
    This API does not substitute a reference world-depth map for GPU readback.
    """
    assert resolution>0 and span>0 and inverse_depth>0 and bias>=0
    right=tuple(matrix[i]*span/2 for i in (0,4,8))
    up=tuple(-matrix[i]*span/2 for i in (1,5,9))
    forward=tuple(matrix[i]/(1 if lose_z_scale else inverse_depth) for i in (2,6,10))
    clip=mul_matrix(matrix,tuple(point)+(1,))
    if dot(normal,SUN)<=0 or not 0<=clip[2]<=1:
        return {'visible_count':9,'visibility':1.0,'taps':[]}
    uv=tuple((clip[i]*.5+.5)*resolution for i in (0,1))
    normal_forward=dot(normal,forward)
    denominator=(-1 if normal_forward<0 else 1)*max(abs(normal_forward),1e-6)
    output=[]
    for oy in (-1,0,1):
        for ox in (-1,0,1):
            x,y=math.floor(uv[0])+ox,math.floor(uv[1])+oy
            if not (0<=x<resolution and 0<=y<resolution):
                output.append({'xy':[x,y],'stored':None,'receiver':None,'lit':True})
                continue
            dx,dy=(x+.5-uv[0])*span/resolution,(y+.5-uv[1])*span/resolution
            displacement=tuple(right[i]*dx-up[i]*dy for i in range(3))
            along=-dot(normal,displacement)/denominator
            receiver=clip[2]+(along-bias)*inverse_depth
            stored=read_depth(x,y)
            assert math.isfinite(stored) and 0<=stored<=1, ('invalid D32',stored)
            output.append({'xy':[x,y],'stored':stored,'receiver':receiver,'lit':receiver<=stored})
    count=sum(t['lit'] for t in output)
    uncertain=[i for i,t in enumerate(output) if t['stored'] is not None and abs(t['receiver']-t['stored'])<=TOLERANCES['production_depth_absolute']]
    fixed=sum(t['lit'] for i,t in enumerate(output) if i not in uncertain)
    return {'visible_count':count,'visibility':count/9,'taps':output,'uv':uv,
            'ambiguous_tap_indices':uncertain,'count_interval':[fixed,fixed+len(uncertain)]}

def controls(native):
    span,inv=8.0,1/32
    matrix=[.25,0,0,0, 0,-.25,0,0, 0,0,inv,0, 0,0,0,1]
    normal=vector(native['normal_bits'])
    point=vector(native['point_bits'])
    stored=unbits(native['world_depth_bits'])*inv
    image={(x,y):stored for y in range(8) for x in range(8)}
    good=production_pcf(matrix,span,inv,.005,point,normal,8,lambda x,y:image[x,y])
    assert good['visible_count']==6, good
    wrong=production_pcf(matrix,span,inv,.005,point,normal,8,lambda x,y:image[x,y],lose_z_scale=True)
    assert wrong['visible_count']!=good['visible_count'], 'lost light Z scale must change literal visibility'
    wrong_resolution=production_pcf(matrix,span,inv,.005,point,normal,4,lambda x,y:stored)
    assert wrong_resolution['visible_count']!=good['visible_count'], 'resolution confusion must change literal visibility'
    assert [t['xy'] for t in good['taps']]==[[3,2],[4,2],[5,2],[3,3],[4,3],[5,3],[3,4],[4,4],[5,4]]
    assert native['counts']==[good['visible_count'],wrong['visible_count'],wrong_resolution['visible_count']], 'native Bend literal and negative controls'
    return {'literal_count':good['visible_count'],'lost_z_scale_count':wrong['visible_count'],
            'wrong_resolution_count':wrong_resolution['visible_count']}

def production_convention(rows,matrix_row):
    matrix=vector(matrix_row['matrix_bits'])
    span=unbits(matrix_row['span_bits'])
    inv=unbits(matrix_row['inverse_depth_bits'])
    bias=unbits(matrix_row['world_bias_bits'])
    right=tuple(matrix[i]*span/2 for i in (0,4,8))
    up=tuple(-matrix[i]*span/2 for i in (1,5,9))
    forward=tuple(matrix[i]/inv for i in (2,6,10))
    for axis in (right,up,forward):
        close(dot(axis,axis),1,5e-7,'actual native matrix recovers world basis')
    assert abs(dot(forward,forward)*inv*inv-1)>.9, 'unrecovered Z row fails basis units'
    checked,coordinate_changes,ambiguities,count_changes=0,0,0,0
    max_error=0
    for row in rows:
        if row['kind']!='receiver' or row['resolution']!=512 or dot(vector(row['normal']),SUN)<=0:
            continue
        point,normal=vector(row['point']),vector(row['normal'])
        clip=mul_matrix(matrix,point+(1,))
        uv=tuple((clip[i]*.5+.5)*512 for i in (0,1))
        taps=row['direct']['taps']
        expected_xy=[tuple(map(int,vector(t[:2]))) for t in taps]
        actual_xy=[(math.floor(uv[0])+x,math.floor(uv[1])+y) for y in (-1,0,1) for x in (-1,0,1)]
        if actual_xy!=expected_xy:
            coordinate_changes+=1
            continue
        def converted_depth(x,y):
            i=expected_xy.index((x,y))
            raw=unbits(taps[i][2])
            return min(1,max(0,(raw-.1)*inv))
        answer=production_pcf(matrix,span,inv,bias,point,normal,512,converted_depth)
        for native_tap,independent in zip(taps,answer['taps']):
            if independent['receiver'] is None:
                continue
            expected=(unbits(native_tap[3])-.1)*inv
            error=abs(independent['receiver']-expected)
            max_error=max(max_error,error)
            close(independent['receiver'],expected,TOLERANCES['production_depth_absolute'],'normalized world-plane and world-bias conventions')
        ambiguities+=len(answer['ambiguous_tap_indices'])
        if answer['visible_count']!=row['direct']['visible']:
            count_changes+=1
            lo,hi=answer['count_interval']
            assert lo<=row['direct']['visible']<=hi, 'converted native reference count outside numerical ambiguity interval'
        checked+=1
    assert checked>100
    return {'receivers_checked':checked,'matrix_vs_basis_texel_coordinate_changes':coordinate_changes,
            'ambiguous_taps':ambiguities,'converted_count_changes':count_changes,
            'max_normalized_receiver_depth_error':max_error,
            'input_depth_is_converted_native_reference_not_gpu_readback':True}

def ownership(boxes,cell):
    for lo,hi,material in boxes:
        if all(a<=x<b for a,b,x in zip(lo,hi,cell)):
            return material
    return 0

def verify(path,constants_path):
    constants=[json.loads(line) for line in constants_path.read_text().splitlines()]
    native_palette={r['material']:vector(r['linear_bits']) for r in constants if r['kind']=='palette'}
    assert set(native_palette)==set(range(1,6))
    for material,actual in native_palette.items():
        for x,y in zip(actual,palette(material)):
            close(x,y,TOLERANCES['palette_linear_absolute'],'independent Oklab vs native pinned palette')
    native_control=next(r for r in constants if r['kind']=='literal_control')
    native_matrix=next(r for r in constants if r['kind']=='production_matrix')
    rows=[json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    bodies={row['state']:row['boxes'] for row in rows if row['kind']=='body'}
    assert set(bodies)=={'intact','carved','repeat','reset'}
    assert bodies['repeat']==bodies['carved'], 'repeat exact original cuboid identity'
    assert bodies['reset']==bodies['intact'], 'reset exact original cuboid identity'
    volumes={state:sum(math.prod(b-a for a,b in zip(lo,hi)) for lo,hi,m in boxes) for state,boxes in bodies.items()}
    assert volumes=={'intact':803970,'carved':803954,'repeat':803954,'reset':803970},volumes
    for state in ('intact','carved'):
        boxes=bodies[state]
        for i,(lo,hi,material) in enumerate(boxes):
            assert material>0 and all(a<b for a,b in zip(lo,hi))
            for blo,bhi,bmaterial in boxes[i+1:]:
                assert any(b<=c or d<=a for a,b,c,d in zip(lo,hi,blo,bhi)), 'original boxes disjoint'
    shadows={(r['state'],r['resolution']):r['basis'] for r in rows if r['kind']=='shadow'}
    assert set(shadows)=={(s,n) for s in ('intact','carved') for n in (128,512)}
    full=[r for r in rows if r['kind']=='full_cache_control']
    assert len(full)==8 and all(r['full']==r['leaf'] for r in full), 'actual full cached field vs sparse leaf controls'
    assert any(len(set(r['full']))>1 for r in full), 'actual nonconstant full cached field control'
    grouped=defaultdict(list)
    paired=defaultdict(dict)
    records=[]
    for row in rows:
        if row['kind']!='receiver':
            continue
        state,n=row['state'],row['resolution']
        basis=shadows[state,n]
        point,normal=vector(row['point']),vector(row['normal'])
        d=row['face']['direction']
        material=row['face']['material']
        assert normal==NORMALS[d]
        assert ownership(bodies[state],row['cell'])==material, ('original owner',row['name'])
        for key,p in (('direct',point),('cache_direct',vector(row['cache_point']))):
            entry=row[key]
            local=vector(entry['local'])
            ln=vector(entry['local_normal'])
            delta=tuple(a-b for a,b in zip(p,vector(basis['eye'])))
            for value,axis in zip(local,('right','up','forward')):
                close(value,dot(delta,vector(basis[axis])),TOLERANCES['world_local_absolute'],'world to original light basis')
            for value,axis in zip(ln,('right','up','forward')):
                close(value,dot(normal,vector(basis[axis])),1e-7,'light normal')
            layout=reference_layout(local,ln,basis,n)
            assert tuple(map(bits,layout))==tuple(entry['uv_slope']), 'actual F32 layout and slope words'
            count=reference_pcf(local,ln,basis,n,entry['taps'],d)
            assert count==entry['visible'], 'direct reference native count'
        assert row['cached']==row['cache_direct']['visible'], 'cached value equals original cache leaf receiver'
        cached,direct=row['cached'],row['direct']['visible']
        base=native_palette[material]
        linear=[daylight(base,normal,value) for value in (cached,direct)]
        display=[display_rgb(value) for value in linear]
        for packed,expected in zip(row['rgb_packed'],display):
            for a,b in zip(rgb_bytes(packed),expected):
                close(a,math.floor(b*255),TOLERANCES['display_byte_absolute'],'pinned display floor')
        assert 0<=cached<=9 and 0<=direct<=9
        grouped[state,n].append(row)
        face=row['face']
        pair_key=(state,row['pose'],row['name'],tuple(face['anchor']),face['direction'],face['material'],tuple(face['size']))
        paired[pair_key][n]=direct
        exposed=ownership(bodies[state],tuple(c+v for c,v in zip(row['cell'],normal)))==0
        if row['pose']!=99:
            assert exposed, 'actual outside-camera hit has an empty outward neighbor'
        records.append({'state':state,'name':row['name'],'pose':row['pose'],'resolution':n,'material':material,
                        'direction':d,'cell':row['cell'],'point':point,'cached_count':cached,'direct_count':direct,
                        'cache_delta':cached-direct,'exposed_owner_neighbor':exposed,
                        'linear_cached':linear[0],'linear_direct':linear[1],
                        'display_cached':display[0],'display_direct':display[1]})
    for control in full:
        matches=[r for r in rows if r['kind']=='receiver' and r['pose']==99 and r['state']==control['state'] and r['resolution']==control['resolution'] and r['face']==control['face']]
        if matches:
            assert sorted(r['cached'] for r in matches)==sorted(control['full']), 'sampled receiver values equal actual full cache'
    summaries=[]
    for (state,n),items in sorted(grouped.items()):
        deltas=Counter(row['cached']-row['direct']['visible'] for row in items)
        summaries.append({'state':state,'resolution':n,'receivers':len(items),
                          'cache_differs':sum(count for delta,count in deltas.items() if delta),
                          'exposed_receivers':sum(r['state']==state and r['resolution']==n and r['exposed_owner_neighbor'] for r in records),
                          'exposed_cache_differs':sum(r['state']==state and r['resolution']==n and r['exposed_owner_neighbor'] and r['cache_delta']!=0 for r in records),
                          'cache_minus_direct_histogram':dict(sorted(deltas.items())),
                          'materials':sorted({r['face']['material'] for r in items}),
                          'directions':sorted({r['face']['direction'] for r in items}),
                          'poses':sorted({r['pose'] for r in items})})
        assert len(items)>=200 and set(r['face']['direction'] for r in items)==set(range(6))
        assert set(r['pose'] for r in items)=={0,1,2,3,99}
        assert any(r['cached']!=r['direct']['visible'] for r in items), 'selection must expose cache approximation'
    assert all(set(p)=={128,512} for p in paired.values())
    resolution_diff=sum(p[128]!=p[512] for p in paired.values())
    assert resolution_diff>0, 'actual reference depth resolution negative control'
    result={'volumes':volumes,'tolerances':TOLERANCES,'summaries':summaries,
            'paired_receivers':len(paired),'resolution_changes_direct_count':resolution_diff,
            'controls':controls(native_control),'production_unit_convention':production_convention(rows,native_matrix),'receiver_provenance':'Original pinned Body and Surface; no canonical Mesh input',
            'reference_effective_resolution':512,'explicit_comparison_resolution':128,
            'gpu_comparisons_performed':False}
    (ROOT/'build/milestone-6-reference/results.json').write_text(json.dumps(result,indent=2)+'\n')
    (ROOT/'build/milestone-6-reference/receivers-derived.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in records))
    print(json.dumps(result,indent=2))
    return result

def gpu_verify(metadata_path,depth_path):
    meta=json.loads(metadata_path.read_text())
    n=meta['resolution']
    assert n==512, 'production acceptance requires explicit 512-square metadata'
    assert meta['depth_format']=='D32_SFLOAT_LE' and meta['depth_origin']=='top_left'
    data=depth_path.read_bytes()
    assert len(data)==4*n*n, 'depth resolution and byte count'
    depth=struct.unpack('<'+'f'*(n*n),data)
    matrix=vector(meta['light_clip_bits'])
    assert len(matrix)==16
    result=[]
    for row in meta['receivers']:
        assert row['provenance'] in ('gpu_world_receiver','gpu_ground_receiver'), 'actual receiver provenance required'
        answer=production_pcf(matrix,unbits(meta['span_bits']),unbits(meta['inverse_depth_bits']),
                              unbits(meta['world_bias_bits']),vector(row['point_bits']),vector(row['normal_bits']),
                              n,lambda x,y:depth[y*n+x])
        if 'observed_visibility_count' in row:
            if answer['taps']:
                lo,hi=answer['count_interval']
            else:
                lo=hi=9
            assert lo<=row['observed_visibility_count']<=hi, (row['name'],answer)
        if 'base_linear_bits' in row:
            base=vector(row['base_linear_bits'])
        elif row.get('material') in range(1,6):
            base=palette(row['material'])
        else:
            base=None
        if base is not None:
            linear=daylight(base,vector(row['normal_bits']),answer['visible_count'])
            answer['linear_rgb']=linear
            answer['display_rgb']=display_rgb(linear)
        result.append({'name':row['name'],**answer})
    print(json.dumps({'input_metadata':str(metadata_path),'input_depth':str(depth_path),
                      'depth_sha256':hashlib.sha256(data).hexdigest(),'results':result},indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('dump',nargs='?',type=Path,default=ROOT/'build/milestone-6-reference/receivers.jsonl')
    parser.add_argument('--constants',type=Path,default=ROOT/'build/milestone-6-reference/matrix-palette.jsonl')
    parser.add_argument('--gpu-metadata',type=Path)
    parser.add_argument('--gpu-depth',type=Path)
    args=parser.parse_args()
    if args.gpu_metadata or args.gpu_depth:
        assert args.gpu_metadata and args.gpu_depth
        gpu_verify(args.gpu_metadata,args.gpu_depth)
    else:
        verify(args.dump,args.constants)
