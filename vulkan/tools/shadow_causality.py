#!/usr/bin/env python3
"""Independent original-cuboid shadow depth and visibility acceptance gate."""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
import re
import struct

import numpy as np

F32_UNIT_ROUNDOFF = 2.0 ** -24
DEPTH_COMPARISON_ABSOLUTE = 3e-7
SUN = np.array([-.45, .35, .82], dtype=float)
SUN /= np.linalg.norm(SUN)
NORMALS = np.array([[-1,0,0], [1,0,0], [0,-1,0], [0,1,0], [0,0,-1], [0,0,1]])


def gamma(operations):
    return operations * F32_UNIT_ROUNDOFF / (1 - operations * F32_UNIT_ROUNDOFF)


def unbits(word):
    return struct.unpack('<f', struct.pack('<I', word))[0]


def vector(words):
    return np.array([unbits(word) for word in words], dtype=float)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


@dataclass(frozen=True)
class LightFrame:
    matrix: np.ndarray
    span: float
    inverse_depth: float
    bias: float
    resolution: int
    subpixel_bits: int

    @classmethod
    def read(cls, path, subpixel_bits):
        data = path.read_bytes()
        if len(data) != 2336:
            raise ValueError('Expected captured 2336-byte std140 frame')
        u = np.frombuffer(data, '<f4').astype(float)
        matrix = u[16:32].reshape(4,4).T
        if not np.isfinite(u[:84]).all() or not np.array_equal(matrix[3], [0,0,0,1]):
            raise ValueError('Nonfinite or nonaffine light frame')
        if u[80] != 512 or u[81] <= 0 or u[82] <= 0 or not 0 <= u[83] <= .005000001:
            raise ValueError('Invalid fixed512 shadow parameters')
        if not 1 <= subpixel_bits <= 24:
            raise ValueError('Invalid device subpixel precision')
        return cls(matrix, float(u[81]), float(u[82]), float(u[83]), 512, subpixel_bits)

    @property
    def inverse(self):
        return np.linalg.inv(self.matrix)

    def pcf(self, point, normal, image):
        clip = self.matrix @ np.r_[point, 1.]
        if normal @ SUN <= 0 or not 0 <= clip[2] <= 1:
            return dict(count=9, taps=[], ambiguous=[])
        uv = (clip[:2] * .5 + .5) * self.resolution
        right = self.matrix[0,:3] * self.span / 2
        up = -self.matrix[1,:3] * self.span / 2
        forward = self.matrix[2,:3] / self.inverse_depth
        nf = normal @ forward
        denominator = math.copysign(max(abs(nf), 1e-6), nf)
        taps = []
        for oy in (-1,0,1):
            for ox in (-1,0,1):
                x,y = np.floor(uv).astype(int) + [ox,oy]
                x,y = int(x),int(y)
                if not (0 <= x < self.resolution and 0 <= y < self.resolution):
                    taps.append(dict(xy=[x,y], stored=None, receiver=None, lit=True))
                    continue
                dx,dy = (np.array([x+.5,y+.5]) - uv) * self.span / self.resolution
                along = -(normal @ (right*dx - up*dy)) / denominator
                receiver = float(clip[2] + (along-self.bias)*self.inverse_depth)
                stored = float(image[y,x])
                taps.append(dict(xy=[x,y], stored=stored, receiver=receiver, lit=receiver <= stored))
        ambiguous = [i for i,t in enumerate(taps) if t['stored'] is not None
                     and abs(t['receiver']-t['stored']) <= DEPTH_COMPARISON_ABSOLUTE]
        return dict(count=sum(t['lit'] for t in taps), uv=uv.tolist(), taps=taps, ambiguous=ambiguous)


def clip_polygon(polygon, normal, offset):
    if len(polygon) == 0:
        return polygon
    result = []
    for a,b in zip(polygon, np.roll(polygon,-1,axis=0)):
        da,db = float(a @ normal-offset),float(b @ normal-offset)
        ina,inb = da <= 0,db <= 0
        if ina:
            result.append(a)
        if ina != inb:
            result.append(a + (b-a)*da/(da-db))
    return np.array(result)


class OriginalCasters:
    def __init__(self, boxes, frame):
        self.boxes = np.asarray(boxes, dtype=np.int64)
        self.frame = frame
        if self.boxes.ndim != 2 or self.boxes.shape[1] != 7:
            raise ValueError('Expected original boxes [lowXYZ,highXYZ,material]')
        if not ((self.boxes[:,:3] < self.boxes[:,3:6]).all()
                and (self.boxes >= 0).all() and (self.boxes < 2**24).all()
                and (self.boxes[:,6] > 0).all()):
            raise ValueError('Invalid original occupied cuboid')
        low,high = self.boxes[:,:3],self.boxes[:,3:6]
        for start in range(0,len(low),128):
            overlaps = (np.maximum(low[start:start+128,None,:],low[None,:,:])
                        < np.minimum(high[start:start+128,None,:],high[None,:,:])).all(axis=2)
            for i in range(overlaps.shape[0]):
                overlaps[i,start+i] = False
            if overlaps.any():
                raise ValueError('Original cuboids must be disjoint')
        points=[]; box_ids=[]; directions=[]; planes=[]
        for box_id,box in enumerate(self.boxes):
            for axis in range(3):
                tangents = [a for a in range(3) if a != axis]
                for side in range(2):
                    plane=box[axis+side*3]
                    corners=[]
                    for u,v in ((0,0),(1,0),(1,1),(0,1)):
                        p=box[:3].copy()
                        p[axis]=plane
                        p[tangents[0]]=box[tangents[0]+u*3]
                        p[tangents[1]]=box[tangents[1]+v*3]
                        corners.append(p)
                    points.append(corners);box_ids.append(box_id)
                    directions.append(axis*2+side);planes.append(plane)
        self.world = np.asarray(points,dtype=float)
        self.box_ids = np.asarray(box_ids)
        self.directions = np.asarray(directions)
        self.axes = self.directions//2
        self.planes = np.asarray(planes,dtype=float)
        homogeneous = np.concatenate([self.world,np.ones((*self.world.shape[:2],1))],axis=2)
        clip = homogeneous @ frame.matrix.T
        if not ((clip[:,:,2] > 0).all() and (clip[:,:,2] < 1).all()):
            raise ValueError('This narrow oracle requires un-clipped original casters')
        self.screen = (clip[:,:,:2]*.5+.5)*frame.resolution
        edge=np.roll(self.screen,-1,axis=1)-self.screen
        area=(edge[:,0,0]*edge[:,1,1]-edge[:,0,1]*edge[:,1,0])
        if (abs(area)<1e-12).any():
            raise ValueError('Edge-on face outside this fixed-light oracle')
        self.edge_normals = np.stack([-edge[:,:,1],edge[:,:,0]],axis=2)*np.sign(area)[:,None,None]
        self.edge_origins=self.screen
        self.edge_lengths=np.linalg.norm(edge,axis=2)
        inverse=frame.inverse
        self.gradient = np.array([[-inverse[a,0]*2/frame.resolution/inverse[a,2],
                                   -inverse[a,1]*2/frame.resolution/inverse[a,2]] for a in self.axes])
        self.intercept=np.array([(p-inverse[a,3]+inverse[a,0]+inverse[a,1])/inverse[a,2]
                                 for a,p in zip(self.axes,self.planes)])
        sums=abs(homogeneous) @ abs(frame.matrix).T
        dot_error=gamma(7)*sums
        viewport_error=gamma(2)*(abs(clip[:,:,:2])+1)*frame.resolution/2
        self.projection_xy_error=(dot_error[:,:,:2]*frame.resolution/2+viewport_error).max(axis=1)
        self.xy_error=2.**(-frame.subpixel_bits)+self.projection_xy_error
        self.z_arithmetic_error=(dot_error[:,:,2]+gamma(7)*abs(clip[:,:,2])).max(axis=1)
        self.depth_error=(abs(self.gradient)*self.xy_error).sum(axis=1)+self.z_arithmetic_error
        self.edge_error=(abs(self.edge_normals)*self.xy_error[:,None,:]).sum(axis=2)
        self.front=(NORMALS[self.directions] @ frame.inverse[:3,2]) < 0
        self.silhouette_edges=np.zeros(self.edge_lengths.shape,dtype=bool)
        box_edges=[]
        for box_id,box in enumerate(self.boxes):
            boundaries=[]
            for index in range(box_id*6,box_id*6+6):
                if not self.front[index]:
                    continue
                for edge_id in range(4):
                    a=self.world[index,edge_id]
                    b=self.world[index,(edge_id+1)%4]
                    adjacent=next(j for j in range(3) if j!=self.axes[index] and a[j]==b[j])
                    side=int(a[adjacent]==box[adjacent+3])
                    if NORMALS[adjacent*2+side] @ frame.inverse[:3,2] > 0:
                        self.silhouette_edges[index,edge_id]=True
                        boundaries.append((index,edge_id))
            if len(boundaries)!=6:
                raise ValueError('Fixed non-axis light must give six box silhouette edges')
            box_edges.append(boundaries)
        indices=np.array(box_edges)
        self.box_edge_normals=self.edge_normals[indices[:,:,0],indices[:,:,1]]
        self.box_edge_origins=self.edge_origins[indices[:,:,0],indices[:,:,1]]
        self.box_edge_error=self.edge_error[indices[:,:,0],indices[:,:,1]]
        self.box_edge_lengths=self.edge_lengths[indices[:,:,0],indices[:,:,1]]
        quantum=2.**(-frame.subpixel_bits)
        self.nearest_grid_screen=np.rint(self.screen/quantum)*quantum
        qe=np.roll(self.nearest_grid_screen,-1,axis=1)-self.nearest_grid_screen
        qn=np.stack([-qe[:,:,1],qe[:,:,0]],axis=2)
        qn*=np.sign((qn*self.edge_normals).sum(axis=2))[:,:,None]
        self.nearest_grid_normals=qn
        self.nearest_grid_lengths=np.linalg.norm(qe,axis=2)
        self.nearest_grid_rounding_stable=(quantum/2-abs(self.nearest_grid_screen-self.screen)>self.projection_xy_error[:,None,:]).all(axis=(1,2))
        self.box_nearest_grid_origins=self.nearest_grid_screen[indices[:,:,0],indices[:,:,1]]
        self.box_nearest_grid_normals=qn[indices[:,:,0],indices[:,:,1]]
        self.box_nearest_grid_rounding_stable=self.nearest_grid_rounding_stable.reshape(-1,6).all(axis=1)

    def face(self, index, xy):
        center=np.array(xy)+.5
        signed=((center-self.edge_origins[index])*self.edge_normals[index]).sum(axis=1)
        quantized_signed=((center-self.nearest_grid_screen[index])*self.nearest_grid_normals[index]).sum(axis=1)
        box_id=self.box_ids[index]
        box_quantized_signed=((center-self.box_nearest_grid_origins[box_id])*self.box_nearest_grid_normals[box_id]).sum(axis=1)
        return dict(box_index=int(self.box_ids[index]), box=self.boxes[self.box_ids[index]].tolist(),
                    direction=int(self.directions[index]), plane=float(self.planes[index]),
                    projected_corners=self.screen[index].tolist(),
                    nearest_grid_corners_pixels=self.nearest_grid_screen[index].tolist(),
                    nearest_grid_edge_signed_distance_pixels=(quantized_signed/self.nearest_grid_lengths[index]).tolist(),
                    nearest_grid_face_covers_tap=bool((quantized_signed>=0).all()),
                    nearest_grid_projection_rounding_stable=bool(self.nearest_grid_rounding_stable[index]),
                    nearest_grid_box_covers_tap=bool((box_quantized_signed>=0).all()),
                    nearest_grid_box_projection_rounding_stable=bool(self.box_nearest_grid_rounding_stable[box_id]),
                    box_silhouette_edge_indices=np.flatnonzero(self.silhouette_edges[index]).tolist(),
                    edge_signed_distance_pixels=(signed/self.edge_lengths[index]).tolist(),
                    edge_bound_pixels=(self.edge_error[index]/self.edge_lengths[index]).tolist(),
                    projection_f32_xy_bound_pixels=self.projection_xy_error[index].tolist(),
                    vertex_xy_bound_pixels=self.xy_error[index].tolist(),
                    depth_gradient_D32_per_pixel=self.gradient[index].tolist(),
                    depth_bound_D32=float(self.depth_error[index]),
                    vertex_and_interpolation_f32_bound_D32=float(self.z_arithmetic_error[index]),
                    ideal_depth_D32=float(self.gradient[index]@center+self.intercept[index]))

    def feasible_translation(self, index, xy, depth):
        center=np.array(xy)+.5
        polygon=self.screen[index].copy()
        epsilon=self.xy_error[index]
        for axis in range(2):
            n=np.eye(2)[axis]
            polygon=clip_polygon(polygon,n,center[axis]+epsilon[axis])
            polygon=clip_polygon(polygon,-n,-center[axis]+epsilon[axis])
        zerror=self.z_arithmetic_error[index]
        polygon=clip_polygon(polygon,self.gradient[index],depth+zerror-self.intercept[index])
        polygon=clip_polygon(polygon,-self.gradient[index],-depth+zerror+self.intercept[index])
        if len(polygon) == 0:
            return None
        original_point=polygon.mean(axis=0)
        delta=center-original_point
        ideal_depth=float(self.gradient[index]@original_point+self.intercept[index])
        return dict(original_point_pixels=original_point.tolist(),
                    permissible_common_vertex_translation_pixels=delta.tolist(),
                    translated_caster_depth_D32=ideal_depth,
                    depth_arithmetic_residual_D32=depth-ideal_depth)

    def check_tap(self, xy, actual):
        center=np.array(xy)+.5
        signed=((center-self.edge_origins)*self.edge_normals).sum(axis=2)
        possible=(signed >= -self.edge_error).all(axis=1)
        mandatory=(signed > self.edge_error).all(axis=1)
        ideal=(signed>=0).all(axis=1)
        depth=self.gradient@center+self.intercept
        best=np.flatnonzero(ideal)
        nearest=None if not len(best) else int(best[np.argmin(depth[best])])
        box_signed=((center-self.box_edge_origins)*self.box_edge_normals).sum(axis=2)
        box_mandatory=(box_signed>self.box_edge_error).all(axis=1)
        front_high=np.where(possible & self.front,depth+self.depth_error,-np.inf).reshape(-1,6).max(axis=1)
        if (box_mandatory & ~np.isfinite(front_high)).any():
            raise ValueError('Mandatory original box has no possible entry face')
        limit=float(np.min(np.r_[1.,(depth+self.depth_error)[mandatory],front_high[box_mandatory]]))
        candidates=np.flatnonzero(possible & (abs(depth-actual)<=self.depth_error) & (depth-self.depth_error<=limit))
        matches=[]
        if actual < 1:
            for index in sorted(candidates,key=lambda i:abs(depth[i]-actual)):
                witness=self.feasible_translation(index,xy,actual)
                if witness is not None:
                    matches.append((int(index),witness))
        if actual == 1 and not mandatory.any() and not box_mandatory.any():
            classification='stable_clear' if not possible.any() else 'bounded_coverage_clear'
            return dict(xy=list(xy),gpu_depth=actual,pass_depth=True,classification=classification,
                        ideal_depth=1. if nearest is None else float(depth[nearest]),
                        original_caster=None if nearest is None else self.face(nearest,xy),
                        matched_caster=None,nearer_optional_casters=[])
        if matches and actual <= limit:
            index,witness=matches[0]
            same_plane=nearest is not None and self.axes[index]==self.axes[nearest] and self.planes[index]==self.planes[nearest]
            closer_optional = possible & ~mandatory & (depth+self.depth_error < actual)
            classification='stable_caster' if same_plane and mandatory[nearest] and not closer_optional.any() else 'bounded_coverage_caster'
            nearer=np.flatnonzero(possible & (depth+self.depth_error<actual))
            blockers=[]
            for i in nearer:
                box_id=int(self.box_ids[i])
                blockers.append(dict(**self.face(int(i),xy), mandatory=bool(mandatory[i]),
                                     box_silhouette_mandatory=bool(box_mandatory[box_id]),
                                     box_silhouette_signed_distance_pixels=(box_signed[box_id]/self.box_edge_lengths[box_id]).tolist(),
                                     box_silhouette_bound_pixels=(self.box_edge_error[box_id]/self.box_edge_lengths[box_id]).tolist(),
                                     excluding_edge_indices=np.flatnonzero(signed[i]<=self.edge_error[i]).tolist()))
            return dict(xy=list(xy),gpu_depth=actual,pass_depth=True,classification=classification,
                        ideal_depth=1. if nearest is None else float(depth[nearest]),
                        original_caster=None if nearest is None else self.face(nearest,xy),
                        matched_caster=dict(**self.face(index,xy),**witness),nearer_optional_casters=blockers)
        return dict(xy=list(xy),gpu_depth=actual,pass_depth=False,classification='unexplained_depth',
                    ideal_depth=1. if nearest is None else float(depth[nearest]),
                    original_caster=None if nearest is None else self.face(nearest,xy),
                    mandatory_nearest_upper_bound=limit,
                    candidates=[self.face(int(i),xy) for i in np.flatnonzero(possible)[:32]])

    def reference_hit(self, xy, basis):
        f=np.float32
        eye=vector(basis['eye']).astype('f4')
        right=vector(basis['right']).astype('f4')
        up=vector(basis['up']).astype('f4')
        direction=vector(basis['forward']).astype('f4')
        scale=f(unbits(basis['scale']))
        x,y=xy
        dx=f(f(f(x)+f(.5))-f(256))/scale
        dy=f(f(f(256)-f(y))-f(.5))/scale
        delta=f(f(right*dx)+f(up*dy))
        axis=self.axes
        t=f(f(f(self.planes.astype('f4')-eye[axis])-delta[axis])/direction[axis])
        covered=t>=f(unbits(basis['near']))
        tangent_uv=[]
        for j in range(3):
            tangent=axis!=j
            low=self.boxes[self.box_ids,j].astype('f4')
            size=(self.boxes[self.box_ids,j+3]-self.boxes[self.box_ids,j]).astype('f4')
            offset=f(f(eye[j]-low)+delta[j])
            uv=f(f(offset+f(t*direction[j]))/size)
            covered &= ~tangent | ((uv>=0)&(uv<=1))
            tangent_uv.append(uv)
        index=int(np.argmin(np.where(covered,t,np.inf)))
        if not covered.any():
            return float(f(1e30)),None,None
        tangents=[j for j in range(3) if j!=axis[index]]
        witness=dict(ray_delta_world=delta.astype(float).tolist(),
                     forward_world=direction.astype(float).tolist(),
                     normalized_face_uv=[float(tangent_uv[j][index]) for j in tangents],
                     distance_world=float(t[index]),
                     normalized_distance_D32=(float(t[index])-unbits(basis['near']))*self.frame.inverse_depth)
        return float(t[index]),index,witness


def original_pcf(row, field, basis):
    f=np.float32
    point=vector(row['point'] if field == 'direct' else row['cache_point']).astype('f4')
    normal=vector(row['normal']).astype('f4')
    eye=vector(basis['eye']).astype('f4')
    axes=[vector(basis[k]).astype('f4') for k in ('right','up','forward')]
    def dot32(a,b):
        return f(f(f(a[0]*b[0])+f(a[1]*b[1]))+f(a[2]*b[2]))
    local=np.array([dot32(f(point-eye),a) for a in axes],dtype='f4')
    local_normal=np.array([dot32(normal,a) for a in axes],dtype='f4')
    if not np.array_equal(local.view('u4'),np.array(row[field]['local'],dtype='u4')):
        raise ValueError('Original receiver basis no longer agrees with pinned F32 inputs')
    scale=f(unbits(basis['scale']));n=f(row['resolution'])
    uv=np.array([f(f(n*f(.5))+f(f(f(local[0]*scale)*n)/f(512))),
                 f(f(n*f(.5))-f(f(f(local[1]*scale)*n)/f(512)))])
    texel=f(f(512)/f(scale*n))
    slope=np.array([f(f(-local_normal[0]/local_normal[2])*texel),
                    f(f(local_normal[1]/local_normal[2])*texel)])
    count=0
    for i,t in enumerate(row[field]['taps']):
        xy=vector(t[:2])
        expected=np.floor(uv)+[i%3-1,i//3-1]
        if not np.array_equal(xy,expected):
            raise ValueError('Original tap coordinate/order differs from independent projection')
        delta=f(f(xy.astype('f4')+f(.5))-uv)
        receiver=f(f(f(local[2]+f(slope[0]*delta[0]))+f(slope[1]*delta[1]))-f(.005))
        if receiver != unbits(t[3]):
            raise ValueError('Original receiver plane threshold differs')
        inside=bool(((xy>=0)&(xy<512)).all())
        if inside != (t[2] is not None):
            raise ValueError('Original clear border metadata differs')
        lit=True if not inside else receiver <= unbits(t[2])
        if bool(t[4]) != lit:
            raise ValueError('Original strict comparison differs')
        count+=int(lit)
    if normal@SUN<=0:
        count=9
    return count


def validate_frame_basis(frame, basis):
    right=vector(basis['right']);up=vector(basis['up']);forward=vector(basis['forward'])
    checks={
        'right':float(np.max(abs(right-frame.matrix[0,:3]*frame.span/2))),
        'up':float(np.max(abs(up+frame.matrix[1,:3]*frame.span/2))),
        'forward':float(np.max(abs(forward-frame.matrix[2,:3]/frame.inverse_depth))),
        'span':abs(frame.span-512/unbits(basis['scale'])),
        'inverse_depth':abs(frame.inverse_depth-1/(frame.span*4-unbits(basis['near']))),
        'world_bias':abs(frame.bias-.005),
    }
    limits=dict(right=1e-7,up=1e-7,forward=1e-7,span=1e-4,inverse_depth=1e-10,world_bias=2e-10)
    if any(checks[key]>limits[key] for key in checks):
        raise ValueError(f'Captured light basis/units differ from pinned source {checks}')
    eye=vector(basis['eye'])
    near=unbits(basis['near'])
    expected=np.array([0.,0.,-near*frame.inverse_depth])
    eye_residual=abs((frame.matrix@np.r_[eye,1.])[:3]-expected)
    translation_bounds=gamma(7)*(abs(frame.matrix[:3])@abs(np.r_[eye,1.]))
    if (eye_residual>translation_bounds).any():
        raise ValueError('Captured light translation does not project the original light eye')
    return dict(absolute_errors=checks,absolute_limits=limits,
                original_eye_clip_residual=eye_residual.tolist(),
                original_eye_clip_F32_bound=translation_bounds.tolist())


def evaluate_state(state, boxes, records, frame, image):
    expected=next(r for r in records if r['kind']=='body' and r['state']==state)['boxes']
    flattened=[a+b+[m] for a,b,m in expected]
    if boxes != flattened:
        raise ValueError('Captured Body before Mesh.build differs from ORIGINAL Body dump')
    basis=next(r['basis'] for r in records if r['kind']=='shadow' and r['state']==state and r['resolution']==512)
    frame_checks=validate_frame_basis(frame,basis)
    if image.shape != (512,512) or not np.isfinite(image).all() or not ((image>=0)&(image<=1)).all():
        raise ValueError('Actual normalized D32 readback must be finite 512square top_left')
    casters=OriginalCasters(boxes,frame)
    receivers=[r for r in records if r['kind']=='receiver' and r['state']==state and r['resolution']==512]
    sunny=[r for r in receivers if vector(r['normal'])@SUN>0]
    tap_sources={}
    visibility=[]
    for row in receivers:
        for field in ('direct','cache_direct'):
            count=original_pcf(row,field,basis)
            if count != row[field]['visible'] or field=='cache_direct' and count!=row['cached']:
                raise ValueError('Independent original PCF differs from native count/cache leaf')
        gpu=frame.pcf(vector(row['point']),vector(row['normal']),image)
        if row in sunny:
            for field in ('direct','cache_direct'):
                for tap in row[field]['taps']:
                    xy=tuple(int(unbits(w)) for w in tap[:2])
                    if not (0<=xy[0]<512 and 0<=xy[1]<512):
                        continue
                    old=unbits(tap[2])
                    if xy in tap_sources and tap_sources[xy]['old_world_depth'] is not None and tap_sources[xy]['old_world_depth']!=old:
                        raise ValueError('Original immutable shadow depth inconsistent across receivers')
                    info=tap_sources.setdefault(xy,dict(old_world_depth=old,reference_uses=0,gpu_uses=0))
                    info['old_world_depth']=old
                    info['reference_uses']+=1
            for tap in gpu['taps']:
                xy=tuple(tap['xy'])
                if tap['stored'] is not None:
                    tap_sources.setdefault(xy,dict(old_world_depth=None,reference_uses=0,gpu_uses=0))['gpu_uses']+=1
        differing=[]
        for i,(gt,rt) in enumerate(zip(gpu['taps'],row['direct']['taps'])):
            rxy=[int(unbits(w)) for w in rt[:2]]
            if gt['xy'] != rxy or gt['lit'] != bool(rt[4]):
                differing.append(dict(index=i,reference_xy=rxy,gpu_xy=gt['xy'],
                                     reference_lit=bool(rt[4]),gpu_lit=gt['lit'],
                                     reference_world_depth=None if rt[2] is None else unbits(rt[2]),
                                     reference_normalized_depth=None if rt[2] is None else min(1.,max(0.,(unbits(rt[2])-unbits(basis['near']))*frame.inverse_depth)),
                                     reference_world_receiver=unbits(rt[3]),
                                     reference_normalized_receiver=(unbits(rt[3])-unbits(basis['near']))*frame.inverse_depth,
                                     gpu_depth=gt['stored'],gpu_receiver=gt['receiver'],
                                     gpu_comparison_ambiguous=i in gpu['ambiguous']))
        visibility.append(dict(name=row['name'],pose=row['pose'],direction=row['face']['direction'],cell=row['cell'],
                               original_cache512=row['cached'],original_direct512=row['direct']['visible'],gpu_direct512=gpu['count'],
                               ambiguous_gpu_taps=gpu['ambiguous'],differing_taps=differing))
    results=[];reference_failures=[]
    for xy,source in sorted(tap_sources.items()):
        original_depth,index,original_witness=casters.reference_hit(xy,basis)
        old=source['old_world_depth']
        if old is not None and old!=original_depth:
            reference_failures.append(dict(xy=list(xy),native_world_depth=old,oracle_world_depth=original_depth))
        result=casters.check_tap(xy,float(image[xy[1],xy[0]]))
        result.update(source)
        result['reference_normalized_depth']=min(1.,max(0.,(original_depth-unbits(basis['near']))*frame.inverse_depth))
        result['gpu_minus_reference_D32']=result['gpu_depth']-result['reference_normalized_depth']
        matched=result.get('matched_caster')
        if not result['pass_depth']:
            result['depth_cause']='unexplained_depth'
        elif abs(result['gpu_minus_reference_D32'])<=DEPTH_COMPARISON_ABSOLUTE:
            result['depth_cause']='agreement_within_comparison_epsilon'
        elif index is None or matched is None or (int(casters.axes[index]),float(casters.planes[index]))!= (matched['direction']//2,matched['plane']):
            result['depth_cause']='different_original_caster_at_bounded_silhouette'
        else:
            result['depth_cause']='same_original_plane_with_bounded_projection_and_depth_interpolation'
        result['reference_f32_world_depth']=original_depth
        result['reference_f32_caster']=None if index is None else dict(**casters.face(index,xy),**original_witness)
        if index is not None:
            result['reference_f32_caster']['exact_native_depth_match']=original_depth==old
        results.append(result)
    by_xy={tuple(r['xy']):r for r in results}
    changed=[]
    for row in visibility:
        if row['differing_taps']:
            for tap in row['differing_taps']:
                gt=by_xy.get(tuple(tap['gpu_xy']))
                rt=by_xy.get(tuple(tap['reference_xy']))
                passed=gt is not None and gt['pass_depth'] and (rt is None or rt['pass_depth'])
                ref_caster=None if rt is None else rt['reference_f32_caster']
                gpu_caster=None if gt is None else gt.get('matched_caster')
                if tap['reference_xy'] != tap['gpu_xy']:
                    cause='receiver_projection_changes_texel'
                elif ref_caster is not None and gpu_caster is not None and (
                        ref_caster['direction']//2 != gpu_caster['direction']//2 or ref_caster['plane'] != gpu_caster['plane']):
                    cause='bounded_original_F32_and_GPU_raster_silhouette_selects_different_original_caster'
                    discrete_grid_evidence=(ref_caster['nearest_grid_box_projection_rounding_stable']
                                            and not ref_caster['nearest_grid_box_covers_tap']
                                            and gpu_caster['nearest_grid_box_covers_tap'])
                    tap['nearest_grid_original_box_omission_and_GPU_box_coverage']=discrete_grid_evidence
                    passed=passed and discrete_grid_evidence
                elif passed:
                    cause='same_original_plane_depth_within_derived_subpixel_interpolation_bound'
                else:
                    cause='unexplained_depth'
                tap['causal_gate_pass']=passed
                tap['cause']=cause
                tap['reference_caster']=ref_caster
                tap['gpu_caster']=gpu_caster
                tap['nearer_optional_casters']=[] if gt is None else gt.get('nearer_optional_casters',[])
                tap['reference_depth_evidence_xy']=None if rt is None else rt['xy']
            changed.append(row)
    classes=Counter(r['classification'] for r in results)
    stable=[r for r in results if r['classification']=='stable_caster']
    failure_records=[r for r in results if not r['pass_depth']]
    failed_changed=[dict(name=r['name'],pose=r['pose'],tap=t['index']) for r in changed for t in r['differing_taps'] if not t['causal_gate_pass']]
    coverage=dict(unique_taps=len(results),sunny_receivers=len(sunny),all_receivers=len(receivers),
                  stable_caster_witnesses=len(stable),stable_clear_witnesses=classes['stable_clear'],
                  classes=dict(classes),stable_caster_directions=dict(Counter(r['matched_caster']['direction'] for r in stable)),
                  stable_caster_materials=dict(Counter(r['matched_caster']['box'][6] for r in stable)),
                  stable_caster_boxes=len(set(r['matched_caster']['box_index'] for r in stable)),
                  stable_shadow_32pixel_tiles=len(set((r['xy'][0]//32,r['xy'][1]//32) for r in stable)))
    coverage['minimum_requirements']=dict(stable_caster_witnesses=1000,stable_clear_witnesses=10,
                                           sunny_directions=[0,3,5],stable_shadow_32pixel_tiles=20)
    enough=(len(stable)>=1000 and classes['stable_clear']>=10
            and all(coverage['stable_caster_directions'].get(d,0)>0 for d in (0,3,5))
            and coverage['stable_shadow_32pixel_tiles']>=20)
    cache_diff=sum(r['original_cache512']!=r['original_direct512'] for r in visibility)
    gpu_diff=sum(r['original_direct512']!=r['gpu_direct512'] for r in visibility)
    reference_gpu_depth_diffs=[r for r in results if r['old_world_depth'] is not None and abs(r['gpu_depth']-min(1.,max(0.,(r['old_world_depth']-unbits(basis['near']))*frame.inverse_depth)))>DEPTH_COMPARISON_ABSOLUTE]
    report=dict(state=state,pass_gate=not reference_failures and not failure_records and not failed_changed and enough,
                body_boxes=len(boxes),body_occupied_cells=int(np.prod(np.array(boxes)[:,3:6]-np.array(boxes)[:,:3],axis=1).sum()),
                frame_basis=frame_checks,coverage=coverage,coverage_requirements_pass=enough,
                reference_caster_depth_exact_pass=not reference_failures,reference_caster_depth_failures=reference_failures,
                visibility=dict(original_cache_vs_direct_count_differences=cache_diff,
                                original_direct_vs_gpu_count_differences=gpu_diff,
                                receivers_with_any_changed_tap=len(changed),
                                compared_changed_taps=sum(len(r['differing_taps']) for r in changed),
                                receivers_with_ambiguous_gpu_comparisons=sum(bool(r['ambiguous_gpu_taps']) for r in visibility),
                                changed_tap_causes=dict(Counter(t['cause'] for r in changed for t in r['differing_taps']))),
                depth_differences_above_comparison_epsilon=len(reference_gpu_depth_diffs),
                original_reference_near_world=unbits(basis['near']),world_bias=frame.bias,
                world_unit_cm=10,world_bias_cm=frame.bias*10,
                derived_bounds=dict(subpixel_quantum_pixels=2.**(-frame.subpixel_bits),
                                    max_vertex_xy_bound_pixels=casters.xy_error.max(axis=0).tolist(),
                                    max_caster_depth_bound_D32=float(casters.depth_error.max()),
                                    minimum_caster_depth_bound_D32=float(casters.depth_error.min())),
                unexplained_depth_count=len(failure_records),unexplained_depths=failure_records,
                failed_changed_taps=failed_changed,changed_receivers=changed,
                cache_direct_gpu_separation=[r for r in visibility if r['original_cache512']!=r['original_direct512'] or r['original_direct512']!=r['gpu_direct512']])
    return report,results,visibility


def read_device(path):
    text=path.read_text()
    names=re.findall(r'^\s*deviceName\s*=\s*(.+)$',text,re.M)
    subpixel=re.findall(r'^\s*subPixelPrecisionBits\s*=\s*(\d+)$',text,re.M)
    if len(names)!=1 or len(subpixel)!=1:
        raise ValueError('Need the actual single capture device and its subPixelPrecisionBits')
    return dict(name=names[0],subpixel_bits=int(subpixel[0]),
                driver_name=re.findall(r'^\s*driverName\s*=\s*(.+)$',text,re.M)[0],
                driver_info=re.findall(r'^\s*driverInfo\s*=\s*(.+)$',text,re.M)[0],
                evidence_sha256=sha256(path))


def run(snapshot, device_path, output, negative_control=None):
    manifest=json.loads((snapshot/'manifest.json').read_text())
    for row in manifest['inputs']:
        if sha256(snapshot/row['name'])!=row['sha256']:
            raise ValueError('Frozen input changed '+row['name'])
    device=read_device(device_path)
    captured_device=next(r for r in manifest['inputs'] if r['name']=='device.txt')
    if device['evidence_sha256']!=captured_device['sha256']:
        raise ValueError('Device precision evidence differs from the frozen capture snapshot')
    records=[json.loads(line) for line in (snapshot/'receivers.jsonl').read_text().splitlines()]
    reports={};detail={};visibility={}
    for state in ('intact','carved'):
        frame=LightFrame.read(snapshot/(state+'.uniform'),device['subpixel_bits'])
        image=np.frombuffer((snapshot/(state+'.shadow')).read_bytes(),'<f4').reshape(512,512).copy()
        boxes=json.loads((snapshot/(state+'.body.json')).read_text())['boxes']
        if negative_control=='clear_missing_pass':
            image.fill(1)
        elif negative_control=='zero_depth':
            image.fill(0)
        elif negative_control=='shifted_one_texel':
            image=np.roll(image,1,axis=1)
        elif negative_control=='stable_depth_spike':
            image[280,123]+=np.float32(.0001)
        elif negative_control=='edge_depth_spike':
            image[300,249]=np.float32(.4)
        report,taps,receivers=evaluate_state(state,boxes,records,frame,image)
        if negative_control:
            report['unexplained_depth_example_limit']=8
            report['unexplained_depths']=report['unexplained_depths'][:8]
        reports[state]=report;detail[state]=taps;visibility[state]=receivers
    result=dict(pass_gate=all(r['pass_gate'] for r in reports.values()),
                negative_control=negative_control,device=device,input_manifest=manifest,
                policy=dict(selection='All unique direct and cache-leaf taps of sunny original512 receivers, plus every production-coordinate tap at those receivers',
                            comparison_depth_epsilon_D32=DEPTH_COMPARISON_ABSOLUTE,
                            f32_unit_roundoff=F32_UNIT_ROUNDOFF,
                            matrix_dot_error='gamma(7)*sum(abs(matrix_row*world_vertex_homogeneous))',
                            viewport_error='gamma(2)*(abs(clipXY)+1)*resolution/2',
                            vertex_xy_error='2^(-actual subPixelPrecisionBits)+matrix_dot_XY_error*resolution/2+viewport_error',
                            caster_depth_error='dot(abs(caster_depth_gradient),vertex_xy_error)+vertex_Z_dot_error+gamma(7)*max(abs(caster_vertex_Z))',
                            coverage='Four signed original projected-face edge inequalities with per-edge L1 displacement bound. No pixel mask.',
                            depth_witness='A clipped original face point realizes observed depth under a bounded common XY translation and the named F32 Z arithmetic bound.',
                            occluders='Every mandatory closer original face and complete box silhouette constrains maximum depth. Every nearer optional face records its excluding edge and box silhouette margins.',
                            strict_comparison='lit iff normalized_receiver_depth <= actual_D32; original bias0.005world and normalized bias0.005*inverseDepth',
                            acceptance='All selected tap depths, exact original F32 caster depths, all changed tap records and broad stable witness coverage must pass'),
                states=reports)
    output.mkdir(parents=True,exist_ok=True)
    (output/'results.json').write_text(json.dumps(result,indent=2)+'\n')
    if not negative_control:
        (output/'tap-evidence.jsonl').write_text(''.join(json.dumps(dict(state=state,**tap))+'\n' for state,taps in detail.items() for tap in taps))
        (output/'visibility.jsonl').write_text(''.join(json.dumps(dict(state=state,**row))+'\n' for state,rows in visibility.items() for row in rows))
    print(json.dumps(dict(pass_gate=result['pass_gate'],negative_control=negative_control,
                          states={s:dict(pass_gate=r['pass_gate'],coverage=r['coverage'],visibility=r['visibility'],
                                         unexplained_depth_count=r['unexplained_depth_count']) for s,r in reports.items()}),indent=2))
    return 0 if result['pass_gate'] else 1


def main():
    root=Path(__file__).resolve().parents[1]/'build/milestone-6-production/shadow-causality'
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot',type=Path,default=root/'snapshot')
    parser.add_argument('--device',type=Path)
    parser.add_argument('--output',type=Path,default=root)
    parser.add_argument('--negative-control',choices=('clear_missing_pass','zero_depth','shifted_one_texel','stable_depth_spike','edge_depth_spike'))
    args=parser.parse_args()
    try:
        return run(args.snapshot,args.device or args.snapshot/'device.txt',args.output,args.negative_control)
    except (ValueError,KeyError,StopIteration) as error:
        print(json.dumps(dict(pass_gate=False,input_error=str(error))))
        return 2


if __name__=='__main__':
    raise SystemExit(main())
