#!/usr/bin/env python3
"""Parse and evaluate the Vulkan replay samples."""
import csv
import math
def quantile(values, p):
    return sorted(values)[max(0, math.ceil(len(values) * p) - 1)] if values else None
def stats(values):
    return {'samples': len(values), 'p50_ms': quantile(values, .5), 'p95_ms': quantile(values, .95), 'p99_ms': quantile(values, .99), 'max_ms': max(values) if values else None, 'mean_ms': sum(values)/len(values) if values else None, 'total_ms': sum(values)}
STAGES = ('carving', 'connectivity', 'surface_generation', 'edit_finalization', 'update_other', 'scene_preparation',
          'vulkan_frame_effect', 'overhead')
VULKAN_STAGES = ('bridge_preparation', 'geometry_generation', 'fence_wait', 'vertex_upload',
                 'image_acquire', 'command_recording', 'submit_and_present', 'renderer_other',
                 'events_and_x11_sync')


def parse_run(lines, exit_code=0, require_vulkan_detail=False):
    frames, stages, vulkan_stages, edits, cuts, attempts, errors = {}, {}, {}, [], [], [], []
    for row in csv.reader(lines):
        if not row:
            continue
        tag = row[0]
        if tag not in ('frame', 'stage', 'vulkan_stage', 'edit', 'cut', 'attempt'):
            errors.append(f'Unexpected row: {row}')
            continue
        try:
            v = [int(x) for x in row[1:]]
            expected = {'frame': 4, 'stage': 9, 'vulkan_stage': 10, 'edit': 8, 'cut': 4, 'attempt': 4}[tag]
            if len(v) != expected or any(x < 0 or x > 0xffffffff for x in v):
                raise ValueError('invalid fields')
            if tag in ('frame', 'stage', 'vulkan_stage'):
                target = {'frame': frames, 'stage': stages, 'vulkan_stage': vulkan_stages}[tag]
                if v[0] in target:
                    errors.append(f'Duplicate {tag} at {v[0]}')
                target[v[0]] = v[1:]
            elif tag == 'edit':
                edits.append(v)
            elif tag == 'cut':
                cuts.append(v)
            else:
                attempts.append(v)
        except ValueError as exc:
            errors.append(f'Invalid {tag}: {exc}')
    if frames.keys() != stages.keys():
        errors.append('Frame/stage timestamps do not match')
    if (require_vulkan_detail or vulkan_stages) and set(vulkan_stages) != set(range(len(frames))):
        errors.append('Vulkan detail rows do not match frame indices')
    previous = 0
    for index, (t, (duration, _, _)) in enumerate(frames.items()):
        if t - previous != duration:
            errors.append(f'End-to-end interval mismatch at {t}')
        previous = t
        if t in stages and sum(stages[t]) != duration:
            errors.append(f'Stage sum mismatch at {t}')
        if t in stages and index in vulkan_stages and sum(vulkan_stages[index]) > stages[t][6]:
            errors.append(f'Vulkan detail exceeds frame effect at {t}')
        own = [e for e in edits if e[0] == t]
        if t in stages and [sum(e[i] for e in own) for i in (4, 5, 6, 7)] != stages[t][:4]:
            errors.append(f'Edit/stage mismatch at {t}')
    if any(e[0] not in frames for e in edits):
        errors.append('Orphan edit')
    # Match every edit with its original complete latency sample, including rejected attempts.
    from collections import Counter
    if Counter((e[1], e[3], e[2]) for e in edits) != Counter((e[0], e[2], e[3]) for e in cuts + attempts):
        errors.append('Edit/latency samples do not match')
    if any(e[2] != 1 for e in cuts):
        errors.append('Non-accepted cut row')
    measured = [t for t in frames if t >= 5_000_000]
    f = [frames[t][0] / 1000 for t in measured]
    c = [v[1] / 1000 for v in cuts]
    a = [{'latency_ms': v[1]/1000, 'status': v[2], 'kind': v[3]} for v in attempts]
    complete = bool(measured) and measured[0] < 5_250_000 and measured[-1] >= 65_000_000
    attempts_ok = len(a) == 6 and all(v['status'] == 2 for v in a) and sum(v['kind'] == 112 for v in a) == 3 and sum(v['kind'] == 113 for v in a) == 3
    workload = exit_code == 0 and complete and len(c) == 33 and attempts_ok and max((v[2] for v in frames.values()), default=0) > 0
    instrumentation = bool(frames) and not errors
    performance = bool(f and c) and quantile(f, .95) <= 33.3 and quantile(c, .95) <= 100 and max(c) <= 250
    detailed = [(t, vulkan_stages[index]) for index, t in enumerate(frames) if index in vulkan_stages]
    measured_detail = [(t, v) for t, v in detailed if t >= 5_000_000 and t in stages]
    return {'exit_code': exit_code, 'complete_window': complete, 'expected_accepted_cuts': 33,
            'raw_frame_samples': len(frames), 'warmup_frame_samples': len(frames)-len(measured),
            'frames': stats(f), 'cuts': stats(c), 'protected_and_empty_attempts': a,
            'max_bodies': max((v[2] for v in frames.values()), default=0),
            'stages': {name: stats([stages[t][i]/1000 for t in measured if t in stages]) for i, name in enumerate(STAGES)},
            'vulkan_stages': ({**{name: stats([v[i]/1000 for _, v in measured_detail])
                                   for i, name in enumerate(VULKAN_STAGES)},
                               'bend_effect_overhead': stats([(stages[t][6]-sum(v))/1000 for t, v in measured_detail])}
                              if vulkan_stages else {}),
            'active_edits': {name: stats([e[i]/1000 for e in edits if e[0] >= 5_000_000 and e[3] == 1]) for name, i in [('carving', 4), ('connectivity', 5), ('surface_generation', 6), ('edit_finalization', 7)]},
            'instrumentation_pass': instrumentation, 'instrumentation_errors': errors,
            'attempts_pass': attempts_ok, 'workload_pass': workload, 'performance_pass': performance,
            'pass': workload and instrumentation and performance}
