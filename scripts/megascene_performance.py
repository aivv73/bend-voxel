import argparse
import hashlib
from functools import lru_cache
import struct
from pathlib import Path

from megascene_inventory import SCHEMA, integer, read_json, require

PROTOCOL = "megascene-performance/2"
SCHEDULES = {"static-perf-v2", "history-perf-v2"}
WARMUP, MEASURED, FRAME_COUNT = 120, 21600, 21721
OFFSETS = (0, 180, 360, 540, 720, 732, 1080, 1260, 1440, 1620)
CUT_FRAMES = tuple(121 + group*1800 + offset for group in range(12) for offset in OFFSETS)
OVERVIEW = CUT_FRAMES[-1] + 120
PHASES = ("startup", "warmup", "ordinary", "edit", "motion")
REVIEW, CHECKPOINT, OVERVIEW_FLAG = 1, 2, 4


def enabled(config):
    return config.get("schedule", config.get("schedule_id")) in SCHEDULES


def admit(config):
    require(config["schedule"] == config["case"]+"-perf-v2" and config["case"] in ("static", "history"),
            "performance schedule/case mismatch")
    expected = dict(preset="small", seed="45", threads="6", profile="full", resolution="1920x1080",
                    warmup="120", frames="21600", fragment_budget="2048")
    require(all(config.get(k) == v for k,v in expected.items()) and
            config.get("diagnostic") is None and config.get("control") is None,
            "performance v2 requires small/seed45/6/full/1080p/120/21600/budget2048")


def finish(frozen, motion_limits=()):
    from megascene_schedule import numeric
    def frames(records):
        return ','.join(record['frame'] for record in records)
    frozen['performance_protocol'] = numeric('protocol', frozen['schedule_id'])
    overview = frozen['performance_protocol']['overview_frame']
    policy = numeric('policy', frozen['warmup_frames'], frozen['measured_frames'], 'true',
                     frames(frozen['actions']), ','.join(map(str, motion_limits)),
                     frames(frozen['review_views']), frames(frozen['required_checkpoints']),
                     overview if overview is not None else '4294967295')
    require(len(policy) == len(frozen['frames']), 'incomplete Bend frame policy')
    for frame, planned in zip(frozen['frames'], policy):
        frame.update(planned)
    validate(frozen)
    return frozen


def validate(frozen):
    require(frozen.get("schedule_id") in SCHEDULES and frozen.get("warmup_frames") == "120" and
            frozen.get("measured_frames") == "21600" and len(frozen["frames"]) == FRAME_COUNT,
            "performance frozen duration mismatch")
    p = frozen["performance_protocol"]
    require(p["version"] == PROTOCOL and p["query_pairs"] == str(FRAME_COUNT) and
            p['ordinary_duration_min_ns']=='10000000000' and p['ordinary_count_min']=='1000',
            "performance metadata mismatch")
    history = frozen["schedule_id"] == "history-perf-v2"
    actions = frozen["actions"]
    require([int(a["frame"]) for a in actions] == (list(CUT_FRAMES) if history else []) and
            [a["action"] for a in actions] == list(map(str,range(len(actions)))),
            "performance action density mismatch")
    require(p["overview_frame"] == (str(OVERVIEW) if history else None) and
            p["history_action_offsets"] == (list(map(str,OFFSETS)) if history else None) and
            p["history_group_frames"] == ("1800" if history else None) and p["history_final_suffix_frames"] == ("179" if history else None) and
            p["history_actions_per_measured_frame"] == ({"numerator":"1", "denominator":"180"} if history else None),
            "performance history regime mismatch")
    checkpoints = {int(p["frame"]) for p in frozen["required_checkpoints"]}
    reviews = {int(p["frame"]) for p in frozen["review_views"]}
    action_at = {int(a["frame"]):a["action"] for a in actions}
    for index,f in enumerate(frozen["frames"]):
        require(f["frame"] == str(index) and f["phase"] in PHASES and
                f["measured_ordinal"] == (str(index-121) if index>120 else None), "performance frame metadata mismatch")
        expected = "startup" if index == 0 else "warmup" if index <=120 else "edit" if index in action_at else None
        require(f["phase"] == expected if expected else f["phase"] in (("ordinary","motion") if history else ("ordinary",)),
                "performance frame population mismatch")
        require(f["actions"] == ([action_at[index]] if index in action_at else []), "performance frame actions mismatch")
        flags = (REVIEW if index in reviews else 0) | (CHECKPOINT if index in checkpoints else 0) | (
            OVERVIEW_FLAG if history and index == OVERVIEW else 0)
        require(integer(f["policy_flags"]) == flags, "performance frame flags mismatch")
    require(not history or any(p["name"] == "history_overview" and int(p["frame"]) == OVERVIEW
                              for p in frozen["required_checkpoints"]), "performance overview checkpoint missing")


def policy_bytes(frozen):
    validate(frozen)
    return b"".join(struct.pack("<II", PHASES.index(f["phase"]), integer(f["policy_flags"])) for f in frozen["frames"])


def scope_keys(config):
    from megascene_report import SCOPE_KEYS
    return SCOPE_KEYS + (("warmup", "frames") if enabled(config) else ())


@lru_cache(maxsize=512)
def settling_age(bottom,offset,speed):
    from megascene_support import motion, value
    for age in range(601):
        current=motion(age,bottom,offset,speed)
        if value(current[1]) == 0 and current == motion(age+1,bottom,offset,speed):
            return age
    raise ValueError("performance fragment did not settle within checked reference range")


def motion_at(steps,bottom,offset,speed):
    from megascene_support import motion
    return motion(min(steps,settling_age(bottom,offset,speed)),bottom,offset,speed)


def compact(value):
    return {k:v for k,v in value.items() if k != 'samples_ns'}


def memory_observations(root,manifest,summary):
    from megascene_report import read_stream
    from megascene_supervisor import audit_allocations, Reference
    resources,errors=read_stream(root/'resources.jsonl',manifest)
    allocations,allocation_errors=read_stream(root/'allocations.jsonl',manifest)
    require(not errors+allocation_errors, 'damaged memory evidence')
    observed=[r for r in resources if r.get('phase')!='preflight']
    values={}
    for field,operation in (('rss_bytes',max),('available_ram_bytes',min),('device_free_bytes',min)):
        samples=[integer(r[field]) for r in observed if field in r]
        values[field]=str(operation(samples)) if samples else None
    supervision=summary['supervision']
    require(values['rss_bytes']==supervision.get('observed_maxima',{}).get('rss_bytes') and
            all(values[k]==supervision.get('observed_minima',{}).get(k) for k in ('available_ram_bytes','device_free_bytes')),
            'memory observations differ from supervision')
    heaps={}
    for r in observed:
        for h in r.get('heaps',[]):
            heaps.setdefault(h['heap'],[]).append(h)
    ledger=audit_allocations(allocations,normal=summary['termination']['cause']=='normal_exit')
    require(ledger==supervision['allocation_ledger'], 'memory ledger differs from supervision')
    reference_bytes=(root/'reference.shared').stat().st_size
    require(reference_bytes==32+integer(supervision['reference_capacity'])*Reference.SLOT,
            'reference reserved bytes differ from supervision')
    return {'scope':'sampled worker extrema over the entire attempt; explicit allocations are ledger totals, not residency',
        'sample_count':str(len(observed)), 'rss_peak_bytes':values['rss_bytes'],
        'available_ram_min_bytes':values['available_ram_bytes'], 'device_free_min_bytes':values['device_free_bytes'],
        'heaps':{key:{'usage_peak_bytes':str(max(integer(h['usage_bytes']) for h in rows)),
                      'budget_min_bytes':str(min(integer(h['budget_bytes']) for h in rows)),
                      'headroom_min_bytes':str(min(integer(h['budget_bytes'])-integer(h['usage_bytes']) for h in rows))}
                 for key,rows in heaps.items()}, 'explicit_vulkan_allocations':ledger,
        'reference_reserved_bytes':str(reference_bytes),
        'frame_policy_bytes':str((root/'frame-policy.bin').stat().st_size),
        'declared_query_pair_capacity':manifest['worker_environment']['MEGASCENE_QUERY_PAIRS'],
        'query_pool_device_bytes':None, 'query_pool_device_bytes_status':'not_measured'}


def report_series(series_path,case):
    from megascene_calibration_series import assess, scope
    from megascene_checkpoints import identity, verify_evidence, mismatch
    from megascene_report import report_bundle
    series=read_json(series_path.read_text())
    require(series.get('protocol')=='performance-v2' and series['scope']['case']==case,
            'performance series case/protocol mismatch')
    assessment=assess(series_path)
    calibration={'schema':SCHEMA,'record_type':'calibration','status':assessment['status'],
                 'scope':assessment['scope'],'reference':str(series_path.with_name('assessment.json'))}
    if assessment['status']=='pass':
        saved=read_json(series_path.with_name('assessment.json').read_text())
        require(saved==assessment, 'retained calibration assessment is stale; rerun assess')
        calibration.update(binding=assessment['binding'],
            reference_sha256=hashlib.sha256(series_path.with_name('assessment.json').read_bytes()).hexdigest())
    rows=[];canonical=[];validation_ids=set()
    for control in series['controls']:
        row={k:control[k] for k in ('kind','mode','archive','output','returncode','binding_error',
                                  'measurement_exclusion') if k in control}
        row.update(evidence_status='unavailable',attempt_id=None,statuses={'calibration':calibration},
                   measured_wall_interval_ns=None,frame_intervals=None,scripted_edit_to_frame_return=None,
                   cpu_stages=None,gpu_submitted_intervals=None,gpu_status='unavailable',memory=None,evidence_errors=[])
        try:
            require(control.get('archive'), 'control archive unavailable')
            root=Path(control['archive'])
            require(root.is_dir(), 'control archive directory unavailable')
            row['evidence_status']='unusable'
            require(control.get('returncode')==0 and not control.get('binding_error') and
                    not control.get('measurement_exclusion'),
                    'control execution or runtime binding failed')
            manifest=read_json((root/'manifest.json').read_text())
            row['attempt_id']=manifest.get('attempt_id')
            identity(manifest,root,manifest['effective'])
            require(scope(manifest['effective'])==series['scope'], 'control configuration differs from series')
            verify_evidence(manifest,root,{'summary.json','validation.json','reference.jsonl','resources.jsonl',
                                          'allocations.jsonl','supervision.json','cpu.jsonl'} |
                            ({'gpu.jsonl'} if control['mode']=='on' else set()))
            summary=report_bundle(root,calibration)
            require(not summary.get('evidence_errors'), 'public evidence integrity errors: '+
                    '; '.join(map(str,summary.get('evidence_errors',[]))))
            memory=memory_observations(root,manifest,summary)
            comparison=None
            if control['mode']=='on':
                comparison=read_json((root/'comparison.json').read_text())
                verify_evidence(manifest,root,{'comparison.json'})
                validation=read_json((root/'validation.json').read_text())
                validation_ids.add(validation['attempt_id'])
            row.update(evidence_status='usable',
                 statuses={k:summary[k] for k in ('schedule_completion','state_correctness','rendering_correctness',
                     'population_qualification','calibration','responsiveness','interactive_pass',
                     'visual_quality','qualified_capacity') if k in summary},
                 measured_wall_interval_ns=summary.get('measured_interval_ns'),
                 frame_intervals={k:compact(v) for k,v in summary['populations'].items() if k in PHASES or k=='combined'},
                 scripted_edit_to_frame_return=compact(summary.get('accepted_edits',summary['populations'].get('accepted_edits',{}))),
                 cpu_stages={stage:{pop:compact(v) for pop,v in groups.items()}
                             for stage,groups in summary.get('stage_populations',{}).items()},
                 gpu_submitted_intervals={k:compact(v) for k,v in summary.get('gpu_execution',{}).get('populations',{}).items()},
                 gpu_status=summary.get('gpu_execution',{}).get('status', 'disabled'), memory=memory)
            if comparison is not None:
                canonical.append({k:comparison.get(k) for k in
                                  ('status','checkpoints','actual_work','edited_work','moving_window','moved_targets')})
        except (OSError,KeyError,ValueError,TypeError,IndexError) as exc:
            row['evidence_errors'].append(str(exc))
        rows.append(row)
    agreement=len(canonical)==3 and len(validation_ids)==1 and all(c['status']=='pass' for c in canonical) and all(mismatch(canonical[0],c) is None for c in canonical[1:])
    return {'configuration':series['scope'],'calibration':{k:v for k,v in assessment.items() if k in
                ('status','reason','statistics','control_count','qualification_scope')},
            'canonical_repeat_agreement':{'status':'pass' if agreement else 'inconclusive',
                'instrumented_repeats':str(len(canonical)), 'scope':'timed canonical checkpoints and work against one complete independent validation'},
            'controls':rows, 'series':str(series_path),
            'continuation_from':series.get('continuation_from'),
            'excluded_attempts':series.get('excluded_attempts',[]),
            'visual_evidence':series.get('validations',{}),
            'qualification':'observations; each correctness, population and calibration gate keeps its actual status'}


def main(argv=None):
    p=argparse.ArgumentParser(description='Compare retained fixed Megascene performance workloads and their calibration controls.')
    p.add_argument('command',choices=('report',))
    p.add_argument('--static-series',required=True)
    p.add_argument('--history-series',required=True)
    p.add_argument('--output',required=True)
    args=p.parse_args(argv)
    result={'schema':SCHEMA,'record_type':'performance_comparison','protocol':PROTOCOL,
            'static':report_series(Path(args.static_series).resolve(),'static'),
            'history':report_series(Path(args.history_series).resolve(),'history'),
            'timing_scope':'CPU frame-effect return and scripted edit-to-return; GPU submitted top-to-bottom; no display/input latency claim',
            'limitations':['Off controls establish endpoint and scalar action agreement only. Transient equality remains unproven.',
                           'Memory extrema cover observed samples. Explicit Vulkan allocation totals do not measure residency.',
                           'Query-pool device bytes are not measured. Reserved reference bytes include common recorder overhead.'],
            'historical_acceptance':'issue68 remains unchanged'}
    from megascene import snapshot
    output=Path(args.output).resolve()
    output.parent.mkdir(parents=True,exist_ok=True)
    snapshot(output,result)
    return 0


if __name__=='__main__':
    import sys
    try:
        sys.exit(main())
    except (ValueError, KeyError, TypeError, OSError) as exc:
        print(str(exc),file=sys.stderr)
        sys.exit(2)
