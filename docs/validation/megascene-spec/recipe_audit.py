import json, math
from itertools import product
import numpy as np

# Independent integer-cell recipe model; no production Bend calls.
def boxes(v):
    owners={}
    def add(owner,x,y,z,m): owners.setdefault(owner,[]).append((x,y,z,m))
    def t(x,y,z,m=2): add('terrain',x,y,z,m)
    t((0,320),(0,1),(0,320),1);t((0,320),(1,8),(0,320))
    t((0,224),(8,24),(0,320));t((288,320),(8,24),(0,320))
    t((224,288),(8,24),(0,240));t((224,288),(8,24),(304,320))
    t((224,288),(22,24),(271,273))
    t((160,208),(24,32+2*v),(16,64));t((160,184),(24,32+2*v),(64,96));t((184,208),(24,28),(64,96))
    def b(x,y,z,m=5): add('building',x,y,z,m)
    H=80+2*v
    for x,z in product(((16,24),(128,136)),repeat=2): b(x,(24,26),z,1)
    b((16,136),(26,28),(16,136));b((16,20),(28,H),(20,132));b((16,136),(28,H),(132,136))
    b((16,64),(28,H),(16,20));b((88,136),(28,H),(16,20));b((64,88),(60,H),(16,20))
    b((132,136),(28,H),(20,56));b((132,136),(28,H),(80,132));b((132,136),(28,44),(56,80));b((132,136),(64,H),(56,80))
    b((76,80),(28,H),(48,72),2);b((76,80),(28,H),(88,112),2);b((76,80),(60,H),(72,88),2)
    for x,z in [((16,48),(16,136)),((72,136),(16,136)),((48,72),(16,96)),((48,72),(120,136))]: b(x,(H,H+3),z,3)
    for j in range(3):
        Z=176+24*j;B=72+v;o=f'span{j}'
        add(o,(22,28),(24,26),(Z+1,Z+7),1);add(o,(124,130),(24,26),(Z+1,Z+7),1)
        add(o,(24,26),(26,B),(Z+3,Z+5),3);add(o,(126,128),(26,B),(Z+3,Z+5),3)
        add(o,(16,136),(B,B+4),(Z,Z+8),2)
    T=58+v%2;R=302+v%2;o='irregular'
    add(o,(280,288),(24,26),(176,184),1);add(o,(280,288),(26,42),(176,184),4)
    add(o,(272,288),(42,50),(168,184),4);add(o,(280,296),(50,T),(176,192),3);add(o,(288,R),(34,50),(184,199),4)
    return owners

def adjacent(a,b):
    for axis in range(3):
        if (a[axis][1]==b[axis][0] or b[axis][1]==a[axis][0]) and all(min(a[k][1],b[k][1])>max(a[k][0],b[k][0]) for k in range(3) if k!=axis): return True
    return False

def box_connected(bs):
    seen={0};work=[0]
    while work:
        i=work.pop()
        for j in range(len(bs)):
            if j not in seen and adjacent(bs[i],bs[j]): seen.add(j);work.append(j)
    return len(seen)==len(bs)

def world(v):
    a=np.zeros((320,90,320),dtype=np.uint8)
    inventory={}
    for owner,bs in boxes(v).items():
        assert box_connected(bs),owner
        assert any(b[3]==1 for b in bs),owner
        n=0
        for x,y,z,m in bs:
            q=a[x[0]:x[1],y[0]:y[1],z[0]:z[1]]
            assert not np.any(q), (v,owner,x,y,z)
            q[:]=m;n+=(x[1]-x[0])*(y[1]-y[0])*(z[1]-z[0])
        inventory[owner]=n
    return a,inventory

def cut(a,p):
    count=0
    for x,y,z in product(*[range(math.floor(c-2),math.ceil(c+2)) for c in p]):
        if not(0<=x<320 and 0<=y<90 and 0<=z<320): continue
        if sum((c+.5-t)**2 for c,t in zip((x,y,z),p))<=4.00001 and a[x,y,z]>1:
            a[x,y,z]=0;count+=1
    return count

def dense_owner(bs):
    return {(x,y,z):m for xr,yr,zr,m in bs for x in range(*xr) for y in range(*yr) for z in range(*zr)}

def components(cells):
    remaining=set(cells);out=[]
    while remaining:
        start=remaining.pop();work=[start];component={start}
        while work:
            x,y,z=work.pop()
            for q in ((x-1,y,z),(x+1,y,z),(x,y-1,z),(x,y+1,z),(x,y,z-1),(x,y,z+1)):
                if q in remaining: remaining.remove(q);component.add(q);work.append(q)
        out.append({'cells':len(component),'anchored':any(cells[q]==1 for q in component),'bottom':min(q[1] for q in component)})
    return sorted(out,key=lambda q:(q['anchored'],q['cells']))

def cut_dict(cells,p):
    dead=[q for q,m in cells.items() if m!=1 and sum((c+.5-t)**2 for c,t in zip(q,p))<=4.00001]
    for q in dead: del cells[q]
    return len(dead)

f=np.float32;dt=f(1)/f(60)
def step(o,v):
    y=f(f(o+f(v*dt))-f(f(f(4.905)*dt)*dt))
    speed=f(v-f(f(9.81)*dt))
    return y,speed

def advance(steps):
    o=v=f(0)
    for _ in range(steps):o,v=step(o,v)
    return float(o),float(v)

result={'scope':'Independent scratch integer-box/dense-cell model only; no production generator, global checkpoint, shader, Vulkan, visual or measured benchmark validation. History occupancy checks freeze moving-beam targets in their known local frame; they do not replay the entire moving world.','variants':[],'support':[],'history':[],'motion':{}}
for v in range(4):
    a,inv=world(v);result['variants'].append({'v':v,'inventory':inv,'cells':sum(inv.values()),'source_boxes':sum(map(len,boxes(v).values()))})
    p=(160,24,160);assert cut(a,p)==16
    cells=dense_owner(boxes(v)['span0']);n1=cut_dict(cells,(25,40,180));c1=components(cells);n2=cut_dict(cells,(127,40,180));c2=components(cells)
    assert n1==n2==16 and all(c['anchored'] for c in c1)
    assert len([c for c in c2 if not c['anchored']])==1 and c2[0]['bottom']==42
    result['support'].append({'v':v,'removed_each':16,'after_first':c1,'after_last':c2})
for q,s in product((2,4),(45,46)):
    N=q*q;arrays={};removed=[]
    for k in range(120):
        b,a=divmod(k,10);n=(5*b+s-45)%N;r=b//N;ix=n%q;iz=n//q;v=(3*ix+5*iz+s-45)%4;Z=176+24*r;B=72+v;T=58+v%2
        if n not in arrays: arrays[n]=world(v)[0]
        points=[(160+12*r,24,160+8*r),(18,48,48+12*r),(25,40,Z+4),(163+12*r,24,160+8*r),(127,40,Z+4),(76,B+2,Z+4),(78,48,54+3*r),(284+3*r,T,180+3*r),([236,230,226][r],23,272),([276,282,286][r],23,272)]
        got=cut(arrays[n],points[a]);assert got>0,(q,s,k,n,points[a]);removed.append(got)
    result['history'].append({'side_m':q*32,'seed':s,'accepted':120,'removed':sum(removed),'by_action_min':[min(removed[a::10]) for a in range(10)],'neighborhoods':len(arrays)})
    del arrays
for frame in range(31,43):
    spans=[]
    for release in (6,18,30):
        o,v=advance(frame-release);assert 4.2+o>0 and v<0;spans.append({'release_frame':release,'offset_m':o,'lowest_world_y_m':4.2+o,'speed_m_s':v})
    result['motion'][frame]=spans
result['motion']['offset12_speed12']=advance(12)
print(json.dumps(result,indent=2))
