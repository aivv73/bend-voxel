"""Validate and summarize fixed-frame stress runs."""
import csv
from collections import Counter
import math

STAGES = ('carving', 'connectivity', 'surface_generation', 'edit_finalization',
          'update_other', 'scene_preparation', 'vulkan_frame_effect', 'overhead')
VULKAN_STAGES = ('bridge_preparation', 'geometry_generation', 'fence_wait',
                 'vertex_upload', 'image_acquire', 'command_recording',
                 'submit_and_present', 'renderer_other', 'events_and_x11_sync')


def stats(values):
    ordered = sorted(values)
    def quantile(p):
        return ordered[max(0, math.ceil(len(ordered) * p) - 1)] if ordered else None
    return {'samples': len(values), 'p50_ms': quantile(.5), 'p95_ms': quantile(.95),
            'p99_ms': quantile(.99), 'max_ms': ordered[-1] if ordered else None,
            'mean_ms': sum(values) / len(values) if values else None,
            'total_ms': sum(values)}


def validate_samples(rows):
    frames, stages, vulkan, edits, cuts, errors = {}, {}, {}, [], [], []
    widths = {'frame': 4, 'stage': 9, 'vulkan_stage': 10,
              'edit': 8, 'cut': 4, 'attempt': 4}
    for row in rows:
        if not row:
            continue
        tag = row[0]
        if tag not in widths:
            errors.append(f'Unexpected row: {row}')
            continue
        try:
            values = [int(value) for value in row[1:]]
            if len(values) != widths[tag] or any(value < 0 or value > 0xffffffff
                                                    for value in values):
                raise ValueError('invalid fields')
            if tag in ('frame', 'stage', 'vulkan_stage'):
                target = {'frame': frames, 'stage': stages, 'vulkan_stage': vulkan}[tag]
                if values[0] in target:
                    errors.append(f'Duplicate {tag} at {values[0]}')
                target[values[0]] = values[1:]
            elif tag == 'edit':
                edits.append(values)
            else:
                cuts.append(values)
        except ValueError as exc:
            errors.append(f'Invalid {tag}: {exc}')
    if frames.keys() != stages.keys():
        errors.append('Frame/stage timestamps do not match')
    if set(vulkan) != set(range(len(frames))):
        errors.append('Vulkan detail rows do not match frame indices')
    previous = 0
    for index, (end, (duration, _, _)) in enumerate(frames.items()):
        if end - previous != duration:
            errors.append(f'End-to-end interval mismatch at {end}')
        previous = end
        if end in stages and sum(stages[end]) != duration:
            errors.append(f'Stage sum mismatch at {end}')
        if end in stages and index in vulkan and sum(vulkan[index]) > stages[end][6]:
            errors.append(f'Vulkan detail exceeds frame effect at {end}')
        own = [edit for edit in edits if edit[0] == end]
        if end in stages and [sum(edit[i] for edit in own) for i in (4, 5, 6, 7)] != stages[end][:4]:
            errors.append(f'Edit/stage mismatch at {end}')
    if any(edit[0] not in frames for edit in edits):
        errors.append('Orphan edit')
    if Counter((edit[1], edit[3], edit[2]) for edit in edits) != Counter(
            (cut[0], cut[2], cut[3]) for cut in cuts):
        errors.append('Edit/latency samples do not match')
    if any(cut[2] != 1 for cut in cuts):
        errors.append('Non-accepted cut row')
    return errors


def parse_stress(lines, exit_code, warmup, measured, edit_every):
    rows = list(csv.reader(lines))
    errors = []
    special = {}
    for tag, width in (('init', 3), ('surface', 2)):
        found = [row for row in rows if row and row[0] == tag]
        if len(found) != 1 or len(found[0]) != width:
            errors.append(f'Expected one {tag} row')
            continue
        try:
            special[tag] = [int(value) for value in found[0][1:]]
        except ValueError:
            errors.append(f'Invalid {tag} row')
    ordinary = [row for row in rows if row and row[0] not in ('init', 'surface')]
    errors.extend(validate_samples(ordinary))
    frames = [row for row in ordinary if row[0] == 'frame']
    stages = [row for row in ordinary if row[0] == 'stage']
    vulkan = [row for row in ordinary if row[0] == 'vulkan_stage']
    edits = [row for row in ordinary if row[0] == 'edit']
    cuts = [row for row in ordinary if row[0] in ('cut', 'attempt')]
    expected = warmup + measured
    if len(frames) != expected or len(stages) != expected or len(vulkan) != expected:
        errors.append(f'Expected {expected} complete frames')
    if exit_code:
        errors.append(f'Process exited {exit_code}')
    if errors:
        return {'pass': False, 'errors': errors}
    frame_data = [[int(value) for value in row[1:]] for row in frames]
    stage_data = [[int(value) for value in row[1:]] for row in stages]
    vk_data = [[int(value) for value in row[1:]] for row in vulkan]
    measured_frames = frame_data[warmup:]
    measured_stages = stage_data[warmup:]
    measured_vk = vk_data[warmup:]
    expected_edits = sum(i >= warmup and edit_every > 0 and i % edit_every == 0
                         for i in range(expected))
    if len(edits) != expected_edits or len(cuts) != expected_edits:
        errors.append(f'Expected {expected_edits} edits and latency samples')
    if any(int(row[4]) != 1 for row in edits):
        errors.append('A stress edit was not accepted')
    if not measured_frames:
        errors.append('No measured frames')
    durations = [row[1] for row in measured_frames]
    total_us = sum(durations)
    acquire_us = sum(row[5] for row in measured_vk)
    return {
        'pass': not errors,
        'errors': errors,
        'scene': special['init'][0],
        'initialization_ms': special['init'][1] / 1000,
        'surface_rectangles': special['surface'][0],
        'solid_cells_start': frame_data[0][2],
        'solid_cells_end': frame_data[-1][2],
        'max_bodies': max(row[3] for row in frame_data),
        'measured_frames': len(measured_frames),
        'measured_seconds': total_us / 1_000_000,
        'throughput_fps': len(measured_frames) * 1_000_000 / total_us,
        'frame': stats([value / 1000 for value in durations]),
        'stages': {name: stats([row[i + 1] / 1000 for row in measured_stages])
                   for i, name in enumerate(STAGES)},
        'vulkan_stages': {name: stats([row[i + 1] / 1000 for row in measured_vk])
                          for i, name in enumerate(VULKAN_STAGES)},
        'acquire_wait_fraction': acquire_us / total_us,
        'edits': len(edits),
        'edit_latency': stats([int(row[2]) / 1000 for row in cuts]),
    }
