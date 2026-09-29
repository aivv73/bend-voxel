#!/usr/bin/env python3
"""Compare a completed shortened schedule with its validated baseline."""

import argparse
import hashlib
from pathlib import Path

from megascene_checkpoints import verify_evidence
from megascene_inventory import SCHEMA, canonical, digest, read_json, require


def load(path):
    root=Path(path)
    manifest=read_json((root/'manifest.json').read_text())
    verify_evidence(manifest,root,('summary.json','validation.json','validation/inventory.json','cpu.jsonl'))
    artifact=next(a for a in manifest['artifacts'] if a['path']=='schedule.json')
    schedule_path=root/'schedule.json'
    require(hashlib.sha256(schedule_path.read_bytes()).hexdigest()==artifact['sha256'],
            'stale frozen schedule')
    summary=read_json((root/'summary.json').read_text())
    validation=read_json((root/'validation.json').read_text())
    inventory=read_json((root/'validation/inventory.json').read_text())
    frozen=read_json(schedule_path.read_text())
    require(manifest['attempt_kind']=='development_observation' and not manifest['synthetic'] and
            summary['attempt_id']==manifest['attempt_id'] and not summary['synthetic'] and
            summary['schedule_completion']['status']=='pass' and
            summary['state_correctness']['status']=='pass' and
            summary['rendering_correctness']['status']=='pass',
            'complete nonsynthetic timed Vulkan attempt required')
    require(validation['status']=='pass' and not validation['synthetic'] and
            validation['attempt_id']!=manifest['attempt_id'] and
            validation['checked_frames']=='3721',
            'distinct complete validation required')
    require(frozen['schedule_id']==manifest['effective']['schedule'] and
            summary['accepted_edits']['count']==str(len(frozen['actions'])),
            'schedule/action evidence mismatch')
    completion=[]
    with (root/'cpu.jsonl').open() as stream:
        for line in stream:
            row=read_json(line)
            if row['record_type']=='checkpoint' and row['frame']=='3720':
                completion.append(row)
    require(len(completion)==1 and 'completion' in completion[0]['names'],
            'missing final canonical checkpoint')
    return manifest,summary,validation,inventory,frozen,completion[0]


def geometry(payload):
    # Canonical body occupancy and surfaces include material and final position,
    # while allowing distinct lifetime IDs for otherwise identical geometry.
    bodies=[{'anchored':b['anchored'],'occupancy':b['occupancy'],
             'surface':b['surface'],'offset_m':b['offset_m']}
            for b in payload['bodies']]
    return sorted(bodies,key=canonical)


def removed(frozen):
    # Keep the observed pre-edit owner with each local cell. This conservatively
    # refuses an equality claim when different body histories alias a coordinate.
    return sorted({(action['pre_edit_hit']['owner'],*cell)
                   for action in frozen['actions']
                   for cell in action['reference_removed_cells']})


def compare(baseline,variant):
    bm,bs,bv,bi,bf,bc=load(baseline)
    vm,vs,vv,vi,vf,vc=load(variant)
    a,b=bm['effective'],vm['effective']
    require(a['case']==b['case'] and a['case'] in ('history','support') and
            a['schedule']==a['case']+'-v1' and b['schedule'] in
            ({'history-12-v1','history-48-v1'} if a['case']=='history' else
             {'support-1-span-v1','support-2-span-v1'}),
            'expected baseline and shortened schedule')
    for key in ('preset','seed','threads','resolution','profile','fragment_budget','warmup','frames','side_m'):
        require(a[key]==b[key], 'baseline/variant mismatch: '+key)
    require(a['preset']=='small' and a['seed']=='45' and a['threads']=='6' and
            a['resolution']=='1920x1080' and a['profile']=='full' and
            a.get('control') is b.get('control') is None,
            'unsupported schedule comparison configuration')
    require(bm['attempt_id']!=vm['attempt_id'] and bv['attempt_id']!=vv['attempt_id'],
            'reused attempt identity')
    initial_inventory=lambda item:{k:v for k,v in item.items() if k!='requested_controls'}
    require(initial_inventory(vi)==initial_inventory(bi) and bv['actual_work']==vv['actual_work'],
            'initial achieved world/work differs')
    require(vf['actions']==bf['actions'][:len(vf['actions'])] and
            all(x['camera']==y['camera'] for x,y in zip(vf['frames'],bf['frames'])) and
            len(vf['frames'])==len(bf['frames'])==3721,
            'variant actions or camera differ from frozen baseline prefix')
    require(vf['variant']['baseline_schedule_id']==a['schedule'] and
            vf['variant']['required_actions']==str(len(vf['actions'])) and
            vf['variant']['omitted_actions']['count']==str(len(bf['actions'])-len(vf['actions'])) and
            vf['variant']['omitted_action_disposition']=='not_required_for_variant' and
            vf['variant']['baseline_completion_equivalence'] is False and
            vs['baseline_schedule_completion']['status']=='not_applicable',
            'shortened schedule mislabeled as baseline completion')
    base_geometry,variant_geometry=geometry(bc['payload']),geometry(vc['payload'])
    base_removed,variant_removed=removed(bf),removed(vf)
    same_geometry=base_geometry==variant_geometry
    same_removed=base_removed==variant_removed
    return {'schema':SCHEMA,'record_type':'schedule_variant_comparison','status':'pass',
            'case':a['case'],'baseline':{'attempt_id':bm['attempt_id'],'validation_id':bv['attempt_id'],
                'schedule_id':a['schedule'],'actions':str(len(bf['actions'])),
                'final_geometry_sha256':digest(base_geometry),'removed_cell_set_sha256':digest(base_removed),
                'final_cells':bc['payload']['cells'],'final_next_id':bc['payload']['next_id'],
                'final_bodies':str(len(bc['payload']['bodies']))},
            'variant':{'attempt_id':vm['attempt_id'],'validation_id':vv['attempt_id'],
                'schedule_id':b['schedule'],'actions':str(len(vf['actions'])),
                'final_geometry_sha256':digest(variant_geometry),'removed_cell_set_sha256':digest(variant_removed),
                'final_cells':vc['payload']['cells'],'final_next_id':vc['payload']['next_id'],
                'final_bodies':str(len(vc['payload']['bodies'])),
                'moving_window':vv.get('moving_window'),
                'edit_population':vs['accepted_edits'],
                'frame_populations':vs['populations'],
                'history_populations':vs.get('history_populations'),
                'edited_work_checkpoints':str(len(vv['edited_work']))},
            'same_final_geometry':same_geometry,'same_removed_cell_set':same_removed,
            'identical_final_geometry_witness':same_geometry and same_removed,
            'retention_specific_attribution':'unavailable' if not (same_geometry and same_removed) else
                'candidate witness only; attribution requires a separate controlled analysis',
            'scope':'separately validated/timed action and camera comparison; no benchmark qualification'}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline',type=Path,required=True)
    p.add_argument('--variant',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    result=compare(args.baseline,args.variant)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_bytes(canonical(result)+b'\n')
    print(args.output)


if __name__=='__main__': main()
