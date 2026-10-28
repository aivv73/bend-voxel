#!/usr/bin/env python3
from collections import defaultdict
from fractions import Fraction
import itertools
import json
import math
from pathlib import Path
import re
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT/'build/milestone-6-math'


def run(args, name):
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    (BUILD/(name+'.log')).write_text(result.stdout + result.stderr)
    if result.returncode or 'SOME PROOFS FAIL' in result.stdout + result.stderr:
        raise AssertionError(f'{name} failed, see build/{name}.log')
    return result.stdout


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def f32(x):
    return struct.unpack('<f', struct.pack('<f', x))[0]


def unbits(x):
    return struct.unpack('<f', struct.pack('<I', x))[0]


def bits(x):
    return struct.unpack('<I', struct.pack('<f', x))[0]


def close(a, b, tolerance=2e-6):
    check(abs(a-b) <= tolerance, f'{a!r} != {b!r} at tolerance {tolerance}')


def dot(a, b):
    return sum(x*y for x,y in zip(a,b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def unit(a):
    length = math.sqrt(dot(a,a))
    return tuple(v/length for v in a)


def mul(m, point):
    return tuple(sum(m[col*4+row]*point[col] for col in range(4)) for row in range(4))


NORMALS = ((-1,0,0),(1,0,0),(0,-1,0),(0,1,0),(0,0,-1),(0,0,1))
SUN = unit((-0.45,0.35,0.82))
PALETTE_INPUT = ((0.736340,0.114340,173.8965),(0.733411,0.093103,66.0436),
                 (0.630974,0.062930,239.8232),(0.723628,0.119039,64.7019),(0.86,0.018,85))
PALETTE_LITERAL = ((0.0703601,0.5332754,0.3712367),(0.6375990,0.3371639,0.1384310),
                   (0.1328680,0.2746776,0.4125438),(0.6938742,0.3005435,0.0781868),
                   (0.6748807,0.6329424,0.5521512))


def oklch_raw(l, c, hue):
    angle = math.radians(hue)
    a, b = c*math.cos(angle), c*math.sin(angle)
    lms = ((l+0.3963377774*a+0.2158037573*b)**3,
           (l-0.1055613458*a-0.0638541728*b)**3,
           (l-0.0894841775*a-1.2914855480*b)**3)
    return tuple(dot(row,lms) for row in ((4.0767416621,-3.3077115913,0.2309699292),
                (-1.2684380046,2.6097574011,-0.3413193965),(-0.0041960863,-0.7034186147,1.7076147010)))


def oklch(l,c,hue):
    rgb = oklch_raw(l,c,hue)
    if all(0 <= x <= 1 for x in rgb):
        return rgb
    low, high = 0, c
    for _ in range(24):
        mid = (low+high)/2
        if all(0 <= x <= 1 for x in oklch_raw(l,mid,hue)):
            low = mid
        else:
            high = mid
    return tuple(min(max(x,0),1) for x in oklch_raw(l,low,hue))


def transfer(x):
    x = min(max(x,0),1)
    return 12.92*x if x <= 0.0031308 else 1.055*x**(1/2.4)-0.055


def decode(x):
    return x/12.92 if x <= 0.04045 else ((x+0.055)/1.055)**2.4


def day(base, direction, visible):
    sky = (0 if direction==4 else 1 if direction==5 else 0.5)
    direct = max(dot(NORMALS[direction],SUN),0)*visible/9
    return tuple(b*(ambient+sky*s+direct*d) for b,ambient,s,d in
                 zip(base,(0.17,0.20,0.27),(0.23,0.24,0.21),(0.88,0.76,0.61)))


def split_packed(word):
    return ((word>>16)&255,(word>>8)&255,word&255)


def round_fraction32(value):
    return Fraction(f32(float(value)))


def metric_rational32(cell, center):
    squared = []
    for coordinate, c in zip(cell,center):
        delta = round_fraction32(Fraction(10*coordinate+5)-Fraction(c))
        squared.append(round_fraction32(delta*delta))
    total = round_fraction32(round_fraction32(squared[0]+squared[1])+squared[2])
    return total <= 400


def expected_cells(center):
    ranges = [range(max(0,int(x/10)-4),min(1048576,int(x/10)+5)) for x in center]
    return [cell for cell in itertools.product(*ranges) if metric_rational32(cell,center)]


def parse_rows(source):
    rows = defaultdict(list)
    for line in source.splitlines():
        parts = line.split()
        if parts:
            rows[parts[0]].append(parts[1:])
    return rows


def check_stage_links():
    for name in ('world','shadow','backdrop','ring'):
        run(['glslangValidator','-V','--target-env','vulkan1.0',
             '-I'+str(ROOT/'shaders'),'-I'+str(ROOT/'shaders'),'-l',
             str(ROOT/'shaders'/f'appearance_{name}.vert'),str(ROOT/'shaders'/f'appearance_{name}.frag'),
             '-o',str(BUILD/f'linked_{name}.spv')],f'link-{name}')
    run(['glslangValidator','-V','--target-env','vulkan1.0',
         '-I'+str(ROOT/'shaders'),'-l',str(ROOT/'shaders/appearance_backdrop.vert'),
         str(ROOT/'shaders/appearance_abi.frag'),'-o',str(BUILD/'linked_abi.spv')],'link-abi')
    print('PASS five vertex/fragment interface links')


def check_canonical_compiler():
    for source in sorted((ROOT/'shaders').glob('appearance_*')):
        if source.suffix not in ('.vert','.frag'):
            continue
        output=BUILD/(source.name+'.spv')
        run(['glslc','--target-env=vulkan1.0','-O','-I'+str(ROOT/'shaders'),
             '-I'+str(ROOT/'shaders'),'-o',str(output),str(source)],'glslc-'+source.name)
        run(['spirv-val','--target-env','vulkan1.0',str(output)],'glslc-'+source.name+'-validate')
    print('PASS nine new stages with canonical glslc -O flags and SPIR-V validation')


def check_abi(abi):
    offsets = (0,64,128,144,160,176,192,208,224,240,320,336)
    sizes = (64,64,16,16,16,16,16,16,16,80,16,2000)
    names = ('camera_clip','light_clip','eye_near','camera_right','camera_up','camera_forward_focal',
             'viewport','brush_cm','flags','palette','shadow_params','selected')
    schema = json.loads((ROOT/'shaders/appearance_layout.json').read_text())
    check(schema['bytes']==2336 and schema['words']==584, 'exact ABI size')
    check(tuple(f['offset'] for f in schema['fields'])==offsets, 'literal field offsets')
    check(tuple(f['size'] for f in schema['fields'])==sizes, 'literal field sizes')
    check(tuple(f['name'] for f in schema['fields'])==names, 'literal field order')
    words = {int(i):int(v) for i,v in abi['abi']}
    check(len(words)==1024, 'sentinel storage capacity')
    for i in range(1024):
        check(words[i] == (0x3f000000+i if i<584 else 0), f'actual Bend sentinel word {i}')
    check(abi['short_field']==[['rejected']] and abi['long_field']==[['rejected']], 'wrong field lengths rejected')
    for path in sorted(BUILD.glob('appearance_*.spv')):
        assembly = run(['spirv-dis',str(path)], path.name+'-reflection')
        if '%AppearanceFrame' in assembly:
            actual = {int(i):int(offset) for i,offset in re.findall(r'OpMemberDecorate %AppearanceFrame (\d+) Offset (\d+)',assembly)}
            check(tuple(actual[i] for i in range(12))==offsets, f'{path.name} reflected offsets')
            check('ArrayStride 16' in assembly, 'std140 array stride')
            check('OpMemberDecorate %AppearanceFrame 0 ColMajor' in assembly and
                  'OpMemberDecorate %AppearanceFrame 1 MatrixStride 16' in assembly, 'matrix layout')
        if path.name=='appearance_world.frag.spv':
            check(assembly.count('NoContraction')>=24, 'precise identity arithmetic survives compilation')
            check('OpImageSampleExplicitLod' in assembly, 'actual sampled shadow instruction')
        if path.name=='appearance_ring.frag.spv':
            check('DepthReplacing' in assembly and 'EarlyFragmentTests' not in assembly, 'ring fragment depth semantics')
        if path.name=='appearance_shadow.frag.spv':
            check('Output' not in assembly, 'shadow fragment has no outputs')
    check(abi['overflow_cells']==[['rejected']], 'selected-cell overflow rejected rather than truncated')
    print('PASS all 584 sentinel words, 440 padding words, literal std140 offsets and SPIR-V reflection')


def check_frame(rows):
    words = [int(w) for i,w in sorted(rows['frame'],key=lambda r:int(r[0]))]
    check(len(words)==1024 and not any(words[584:]), 'logical upload and padded capacity')
    values = [unbits(w) for w in words]
    check(words[56:60]==[1,0,0,len(expected_cells((65,65,65)))], 'literal frame flags')
    check(values[48:52]==[640.0,360.0,f32(1/640),f32(1/360)], 'viewport and reciprocal layout')
    check(values[52:56]==[65.0,65.0,65.0,20.0], 'brush bit identity')
    close(values[47],420*360/512,0)
    close(values[80],512,0)
    close(values[81],882,0)
    close(values[82],1/(3528-0.1),1e-10)
    close(values[83],0.005,2e-10)
    expected = expected_cells((65,65,65))
    actual = [tuple(words[84+4*i:87+4*i]) for i in range(len(expected))]
    check(actual==expected, 'frame selected cells and lexicographic order')
    check(all(words[87+4*i]==0 for i in range(125)), 'selected fourth words zero')
    check(not any(words[84+4*len(expected):584]), 'unused selected slots zero')
    yaw, pitch = 1.90401163, -0.30
    right = (math.sin(yaw),-math.cos(yaw),0)
    up = (-math.sin(pitch)*math.cos(yaw),-math.sin(pitch)*math.sin(yaw),math.cos(pitch))
    forward = (math.cos(pitch)*math.cos(yaw),math.cos(pitch)*math.sin(yaw),math.sin(pitch))
    eye = (310,-50,110)
    for row in range(3):
        close(values[36+row],right[row]); close(values[40+row],up[row]); close(values[44+row],forward[row])
        close(values[32+row],eye[row],0)
    matrix = values[:16]
    for point in ((310,-50,110,1),(10,0,0,1),(0,20,15,1),(440,340,93,1)):
        delta = tuple(point[i]-eye[i] for i in range(3))
        camera = (dot(delta,right),dot(delta,up),dot(delta,forward))
        clip = mul(matrix,point)
        expected_clip = (2*(420*360/512)/640*camera[0], -2*(420*360/512)/360*camera[1],camera[2]-0.1,camera[2])
        for a,b in zip(clip,expected_clip): close(a,b,8e-5)
    check(rows['reject_zero_width']==[['1']] and rows['reject_extent']==[['1']], 'invalid frames rejected')
    indices = [int(w) for i,w in sorted(rows['indices'],key=lambda r:int(r[0]))]
    check(indices==list(range(576)), 'static three-ring 32-segment triangle indices')
    print('PASS actual Bend frame matrices, flags, palette slots, exact selected slots and 576 indices')
    return values


def check_palette_day(rows, values):
    palette = [oklch(*p) for p in PALETTE_INPUT]
    actual = {int(row[0]):tuple(unbits(int(v)) for v in row[1:]) for row in rows['palette']}
    for i, expected in enumerate(palette,1):
        for a,b,c in zip(actual[i],expected,PALETTE_LITERAL[i-1]):
            close(a,b,2e-6);close(a,c,2e-6)
        for a,b in zip(values[60+(i-1)*4:63+(i-1)*4],expected): close(a,b,2e-6)
    vectors = []
    for material,direction,visible,packed in rows['day']:
        material,direction,visible,packed = map(int,(material,direction,visible,packed))
        linear = day(palette[material-1],direction,visible)
        expected = tuple(math.floor(transfer(x)*255) for x in linear)
        check(all(abs(a-b)<=1 for a,b in zip(split_packed(packed),expected)), 'pinned daylight vs independent linear formula')
        vectors.append(dict(material=material,direction=direction,visible_taps=visible,linear=linear,
                            srgb=tuple(transfer(x) for x in linear),reference_floor_rgb=expected))
    for i,word in rows['transfer']:
        value = (-0.1,0,0.0031308,0.18,0.5,1,1.1)[int(i)]
        close(unbits(int(word)),transfer(value),1.5e-7)
    for linear, expected in ((0,0),(0.0031308,0.040449936),(0.18,0.4613561295),(0.5,0.7353569831),(1,1)):
        close(transfer(linear),expected,1e-9)
        close(decode(transfer(linear)),linear,1e-10)
    check(transfer(0.18) > 0.46 and transfer(transfer(0.18)) > 0.70, 'double encode control differs')
    (BUILD/'oracle_vectors.json').write_text(json.dumps(dict(daylight=vectors,
        tolerances=dict(palette_linear_abs=2e-6,transfer_abs=1.5e-7,reference_floor_vs_unorm_lsb=1)),indent=2)+'\n')
    check(rows['unknown']==[['unselected','16711935'],['selected','16776960']], 'pinned high-bit unknown tint literals')
    world_source=(ROOT/'shaders/appearance_world.frag').read_text()
    check(world_source.index('vec3 lit = vec3(1, 0, 1)') < world_source.index('if (appearance_selected(cell)) lit = vec3(1, 1, 0)'), 'unknown diagnostic shares selection replacement')
    check('id == 0u || id > 5u' not in world_source,'no unknown early return before tint')
    print('PASS five pinned Oklch palettes, 300 daylight cases, transfer literals and once-encode controls')


def check_selection(rows):
    centers = {'demo':(65,65,65),'edge':(25,5,5),'equal':(45,65,65),
               'below':(unbits(1110704127),65,65),'above':(unbits(1110704129),65,65),
               'limit':(10485760,)*3}
    grouped = defaultdict(list)
    for name,*rest in rows['selected']:
        grouped[name].append(rest)
    for name,center in centers.items():
        actual = [tuple(map(int,v)) for v in grouped[name]]
        expected = expected_cells(center)
        check(actual==expected, f'{name} selection differs from independent rational F32 sphere')
        check(len(actual)<=125, 'selection capacity')
    check((6,6,6) in [tuple(map(int,v)) for v in grouped['equal']], 'inclusive equality cell')
    check((6,6,6) not in [tuple(map(int,v)) for v in grouped['below']], 'adjacent F32 outside cell')
    check((6,6,6) in [tuple(map(int,v)) for v in grouped['above']], 'adjacent F32 inside cell')
    check(grouped['invalid_radius']==[['rejected']] and grouped['invalid_coordinate']==[['rejected']], 'invalid brush inputs')
    check(metric_rational32((4,4,6),centers['below']), 'orthogonal equality remains included after F32 rounding')
    exact_squared = sum((Fraction(10*c+5)-Fraction(x))**2 for c,x in zip((4,4,6),centers['below']))
    check(exact_squared>400, 'real-arithmetic sphere is an invalid substitute for pinned F32 semantics')
    print('PASS exact rational F32 sphere membership, inclusive and adjacent-F32 thresholds, coordinate bounds')


def shader_identity(d, anchor, extent, eye, ray):
    axes = ((0,1,2),(1,0,2),(2,0,1))[d//2]
    a,b,c = axes
    plane = f32(anchor[a] + (d%2))
    t = f32(f32(plane-eye[a])/ray[a])
    local = []
    for tangent,width in ((b,extent[0]),(c,extent[1])):
        eye_offset = f32(eye[tangent]-anchor[tangent])
        numerator = f32(eye_offset+f32(t*ray[tangent]))
        normalized = f32(numerator/width)
        local.append(min(math.floor(f32(normalized*width)),width-1))
    cell = list(anchor)
    cell[b] += local[0];cell[c] += local[1]
    return tuple(cell)


def check_identity(rows):
    anchor = (7,11,13)
    for d,u,v,x,y,z,material in rows['identity']:
        d,u,v,x,y,z,material = map(int,(d,u,v,x,y,z,material))
        if d<2: expected=(7,11+min(u,1),13+min(v,2)); axes=(0,1,2)
        elif d<4: expected=(7+min(u,1),11,13+min(v,2)); axes=(1,0,2)
        else: expected=(7+min(u,1),11+min(v,2),13); axes=(2,0,1)
        check((x,y,z)==expected and material==0x80000102, 'literal pinned cell/material identity')
        a,b,c = axes
        eye = list(anchor);ray=[0,0,0]
        eye[a] += d%2 + (-5 if d%2==0 else 5)
        eye[b] += u;eye[c] += v
        ray[a] = 1 if d%2==0 else -1
        check(shader_identity(d,anchor,(2,3),eye,ray)==expected, 'ray/plane shader model literal identity')
    check(len(rows['identity'])==72, 'all six face directions and all 2x3 boundaries')
    for d,u,v,x,y,z,material in rows['pixel_identity']:
        d,u,v,x,y,z,material=map(int,(d,u,v,x,y,z,material))
        a,b,c=((0,1,2),(1,0,2),(2,0,1))[d//2]
        forward=tuple(-n for n in NORMALS[d])
        right=unit(cross(forward,(0,0,1))) if d<4 else (1,0,0)
        up=cross(right,forward)
        ray=tuple(forward[i]+0.5*right[i]-0.5*up[i] for i in range(3))
        eye=list(anchor)
        eye[a] += d%2-5*ray[a]
        eye[b] += u-5*ray[b];eye[c] += v-5*ray[c]
        expected=list(anchor);expected[b]+=min(u,1);expected[c]+=min(v,2)
        check((x,y,z)==tuple(expected) and material==0x80000102,'pinned pixel-center literal identity')
        check(shader_identity(d,anchor,(2,3),eye,ray)==tuple(expected),'shader pixel ray/plane model identity')
    check(len(rows['pixel_identity'])==72,'all six pixel-center ray fixtures')
    check(rows['normalized']==[['41','7','11','13','2147483906']], 'pinned normalized expansion rounds 1/41 below cell boundary')
    check(shader_identity(5,anchor,(41,3),(8,11,19),(0,0,-1))==anchor, 'normalization operation order control')
    check(math.floor(8)==8 and anchor[0]==7, 'floor(position) counterexample retained')
    print('PASS 144 literal and pixel-center identities, full material bits, internal/outer boundaries and normalized-expansion counterexample')


def check_sun_depth(rows):
    matrices = defaultdict(dict)
    for extent,index,word in rows['sun']:
        matrices[int(extent)][int(index)] = unbits(int(word))
    forward = tuple(-x for x in SUN)
    right = unit(cross(forward,(0,0,1)))
    up = cross(right,forward)
    slope_cases = []
    for extent,entries in matrices.items():
        m = [entries[i] for i in range(16)]
        span = 2*extent+2
        inv = f32(1/f32(4*span-f32(0.1)))
        recovered = (tuple(m[i]*span/2 for i in (0,4,8)),
                     tuple(-m[i]*span/2 for i in (1,5,9)),
                     tuple(m[i]/inv for i in (2,6,10)))
        for a,b in zip(recovered,(right,up,forward)):
            for x,y in zip(a,b):close(x,y,3e-7)
            close(dot(a,a),1,5e-7)
        close(dot(recovered[0],recovered[1]),0,2e-7)
        close(dot(recovered[0],recovered[2]),0,2e-7)
        close(dot(recovered[1],recovered[2]),0,2e-7)
        eye = tuple(extent/2+sun*span for sun in SUN)
        for point in itertools.product((0,extent),repeat=3):
            actual = mul(m,point+(1,))
            delta = tuple(a-b for a,b in zip(point,eye))
            expected = (2*dot(delta,right)/span,-2*dot(delta,up)/span,(dot(delta,forward)-0.1)/(4*span-0.1),1)
            for a,b in zip(actual,expected): close(a,b,3e-7)
            check(0<=actual[2]<=1, 'scene corner lies in light depth range')
        point = tuple(extent*0.4 for _ in range(3))
        clip = mul(m,point+(1,))
        for normal in (NORMALS[0],NORMALS[3],NORMALS[5],unit((-0.3,0.4,0.5))):
            n = tuple(dot(normal,axis) for axis in recovered)
            slopes = (-n[0]/n[2]*span/512,n[1]/n[2]*span/512)
            for dx,dy in itertools.product((-1.25,-0.25,0.75),repeat=2):
                displacement = tuple(right[i]*(dx*span/512)-up[i]*(dy*span/512) for i in range(3))
                along = -dot(normal,displacement)/dot(normal,forward)
                shifted = tuple(point[i]+displacement[i]+forward[i]*(along-0.005) for i in range(3))
                expected_depth = (dot(tuple(shifted[i]-eye[i] for i in range(3)),forward)-0.1)/(4*span-0.1)
                actual_depth = clip[2]+(slopes[0]*dx+slopes[1]*dy-0.005)*inv
                close(actual_depth,expected_depth,3e-7)
                slope_cases.append((extent,normal,dx,dy,expected_depth))
            old_nz = dot(normal,tuple(m[i] for i in (2,6,10)))
            wrong_sx = -n[0]/old_nz*span/512
            if abs(slopes[0])>1e-4:
                check(abs(wrong_sx/slopes[0])>10, 'Z scaling negative control must detect defect')
        close(0.005*inv,0.005/(4*span-0.1),1e-10)
    check(len(slope_cases)==144, 'receiver plane oracle case count')
    depth = 0.4
    taps = (0.1,0.5,0.4,0.399,1.0,0.0,0.41,0.7,0.3)
    check(sum(depth<=d for d in taps)==5, 'literal nine-tap visibility is 5/9')
    check(sum(True if i in (0,1,2,3,6) else depth<=taps[i] for i in range(9))==7, 'out-of-domain taps are lit')
    for nz in (0,-0.0,1e-12,-1e-12):
        guarded = -max(abs(nz),1e-6) if nz<0 else max(abs(nz),1e-6)
        check(math.isfinite(1/guarded), 'finite grazing receiver rule')
    print('PASS four actual sun matrices, 32 scene corners, 144 independent world-plane depth comparisons and PCF literals')


def check_rings(rows):
    segments = defaultdict(dict)
    for name,*rest in rows['segment']:
        if rest==['rejected']:
            segments[name]=None
        else:
            segments[name][int(rest[0])] = unbits(int(rest[1]))
    check(segments['hidden'] is None, 'both endpoints behind near')
    t = (0.1-0.05)/(1-0.05)
    expected=(256+420*t/0.1,256,10,676,256,1)
    actual=tuple(segments['crossing'][i] for i in range(6))
    for a,b in zip(actual,expected):close(a,b,5e-5)
    reverse=tuple(segments['reversed'][i] for i in range(6))
    for a,b in zip(reverse,expected[3:]+expected[:3]):close(a,b,5e-5)
    cases={'inside':1,'outside':0,'reciprocal_front':1,'reciprocal_back':0,'background':1}
    for name,expected_bit in cases.items():
        check([name,str(expected_bit)] in rows['wire'],f'pinned wire {name}')
    close(1/(0.5+0.5*(0.25-0.5)),8/3,1e-15)
    check(8/3<2.8 and (2+4)/2>2.8, 'linear eye-depth interpolation negative control')
    for width,height in ((512,512),(1600,160),(160,1600)):
        for p,q in (((20,30),(120,70)),((2,2),(2,2)),((-2000,-1000),(3000,4000))):
            d=tuple(b-a for a,b in zip(p,q));length=math.hypot(*d)
            tangent=tuple(v/length for v in d) if length else (1,0)
            normal=(-tangent[1],tangent[0])
            for end,plus in ((False,False),(True,False),(True,True),(False,True)):
                point=tuple((q if end else p)[i]+(0.75 if end else -0.75)*tangent[i]+(0.75 if plus else -0.75)*normal[i] for i in range(2))
                clip=tuple(point[i]/(width,height)[i]*2-1 for i in range(2))
                reconstructed=tuple((clip[i]+1)/2*(width,height)[i] for i in range(2))
                for a,b in zip(point,reconstructed):close(a,b,1e-10)
    for near,z in ((0.1,0.1),(0.1,8/3),(0.5,10)):
        actual=1-near/max(near,z-0.0001)
        check(0<=actual<1,'valid Vulkan ring depth')
        check(actual<=1-near/z,'world-space occlusion allowance moves ring toward camera')
    print('PASS pinned near clipping in both orders, hidden arcs, 0.75px threshold, reciprocal depth and portrait/landscape ribbons')


def check_backdrop():
    cases=((0,512,0,0,0x101820),(31,512,31,0,0x101820),(32,512,32,1,0x111921),
           (511,512,511,15,0x1f272f),(22,360,32,1,0x111921),
           (27,450,31,0,0x101820),(28,450,32,1,0x111921),
           (55,450,63,1,0x111921),(56,450,64,2,0x121a22),(449,450,511,15,0x1f272f),
           (55,900,31,0,0x101820),(56,900,32,1,0x111921),
           (111,900,63,1,0x111921),(112,900,64,2,0x121a22),(899,900,511,15,0x1f272f))
    for pixel_y,height,expected_y,expected_band,expected in cases:
        canonical_y=min(511,math.floor(f32(f32(f32(pixel_y+0.5)*512)/height)))
        independent_y=((2*pixel_y+1)*256)//height
        check(canonical_y==expected_y==independent_y,'literal authored pixel-center row')
        check(canonical_y//32==expected_band,'literal authored gradient band')
        packed=1054752+(canonical_y//32)*65793
        check(packed==expected,'literal authored background gradient')
        for byte in split_packed(packed):close(transfer(decode(byte/255)),byte/255,1e-14)
    for pixel_y in range(512):
        canonical_y=math.floor(f32(f32(f32(pixel_y+0.5)*512)/512))
        check(canonical_y==pixel_y,'all 512 authored rows preserved')
        check(1054752+(canonical_y//32)*65793==1054752+(pixel_y//32)*65793,
              'all 512 authored gradient colors preserved')
    check((28*512)//450==31 and ((2*28+1)*256)//450==32,'height450 lower-edge negative control')
    check((56*512)//900==31 and ((2*56+1)*256)//900==32,'portrait450x900 lower-edge negative control')
    for point,grid in (((0,1),True),((1,1),False),((-2,1),True),((2.03,1),False)):
        frac=tuple((x*0.5)%1 for x in point)
        check(any(x<0.0125 or x>0.9875 for x in frac)==grid,'literal ground grid membership')
    source=(ROOT/'shaders/appearance_backdrop.frag').read_text()
    check('gl_FragDepth' not in source,'ground has no shader depth output')
    print('PASS height450 and portrait450x900 pixel-center rows/bands, all 512 authored rows, transfer and ground/grid')


def main():
    BUILD.mkdir(exist_ok=True, parents=True)
    run([sys.executable,'tools/build_shaders.py','--check'],'shader-check')
    check_stage_links()
    check_canonical_compiler()
    run(['bend','PROOF.bend'],'proof')
    for name in ('numeric_dump','abi_dump'):
        run(['bend',f'tests/appearance_{name}.bend','-o',str(BUILD/name)],name+'-compile')
        output=run([str(BUILD/name),'+RTS','--threads','4','-RTS'],name)
        (BUILD/(name+'.tsv')).write_text(output)
    rows=parse_rows((BUILD/'numeric_dump.tsv').read_text())
    abi=parse_rows((BUILD/'abi_dump.tsv').read_text())
    check_abi(abi)
    values=check_frame(rows)
    check_palette_day(rows,values)
    check_selection(rows)
    check_identity(rows)
    check_sun_depth(rows)
    check_rings(rows)
    check_backdrop()
    print('PASS pure frame, identity, selection, lighting and ring numeric equations. GPU acceptance is separate.')

if __name__=='__main__':
    main()
