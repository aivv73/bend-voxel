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


def summarize_views(rows, mode, warmup, measured):
    errors = []
    if mode == 'static':
        if rows:
            errors.append('Unexpected view rows for a static case')
        return {}, errors
    if len(rows) != warmup + measured:
        errors.append(f'Expected {warmup + measured} view rows')
    views = []
    for index, row in enumerate(rows):
        try:
            if len(row) != 11 or int(row[1]) != index:
                raise ValueError('invalid frame index or field count')
            camera = tuple(float(value) for value in row[2:7])
            kind = int(row[7])
            aim = tuple(float(value) for value in row[8:11])
            if not all(math.isfinite(value) for value in camera + aim) or kind not in (0, 1, 2, 3):
                raise ValueError('invalid camera or aim')
            views.append((camera, kind, aim))
        except ValueError as exc:
            errors.append(f'Invalid view row {index}: {exc}')
    if errors:
        return {}, errors
    sample = views[warmup:]
    camera_positions = len({camera for camera, _, _ in sample})
    aim_positions = len({aim for _, kind, aim in sample if kind != 0})
    target_frames = sum(kind != 0 for _, kind, _ in sample)
    preview_frames = sum(kind == 1 for _, kind, _ in sample)
    required_positions = min(12, max(2, measured // 4))
    if mode == 'camera':
        if camera_positions < required_positions or target_frames:
            errors.append('Camera workload did not move with aim disabled')
    elif mode == 'aim':
        if camera_positions != 1 or aim_positions < required_positions or preview_frames < measured // 4:
            errors.append('Aim workload did not sweep removable targets with a fixed camera')
    elif mode in ('carve', 'bridge'):
        if camera_positions != 1 or target_frames:
            errors.append('Destruction overview moved or enabled aim')
    elif mode == 'fragments':
        if camera_positions < required_positions or preview_frames < measured // 4:
            errors.append('Fragment workload did not follow removable moving bodies')
    else:
        errors.append(f'Unknown view mode {mode}')
    return {'camera_positions': camera_positions, 'aim_positions': aim_positions,
            'target_frames': target_frames, 'preview_frames': preview_frames}, errors


def parse_stress(lines, exit_code, warmup, measured, edit_every, view_mode='static', world_scale=None):
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
    views = [row for row in rows if row and row[0] == 'view']
    view_summary, view_errors = summarize_views(views, view_mode, warmup, measured)
    errors.extend(view_errors)
    ordinary = [row for row in rows if row and row[0] not in ('init', 'surface', 'view', 'world', 'mesh_cache', 'bodies')]
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
    limit = {'bridge': 2, 'fragments': 16, 'carve': 75}.get(view_mode, 5000)
    batch = 8 * (world_scale or 1) if view_mode == 'fragments' else 1
    edit_frames = {i: batch for i in range(warmup, expected)
                   if edit_every > 0 and (i - warmup) % edit_every == 0
                   and (i - warmup) // edit_every < limit}
    expected_edits = sum(edit_frames.values())
    if len(edits) != expected_edits or len(cuts) != expected_edits:
        errors.append(f'Expected {expected_edits} edits and latency samples')
    if any(int(row[4]) != 1 for row in edits):
        errors.append('A stress edit was not accepted')
    if not measured_frames:
        errors.append('No measured frames')
    district_summary, district_errors = summarize_district(rows, frame_data, edits, edit_frames,
        world_scale, view_mode, warmup, measured) if world_scale is not None else ({}, [])
    errors.extend(district_errors)
    durations = [row[1] for row in measured_frames]
    total_us = sum(durations)
    acquire_us = sum(row[5] for row in measured_vk)
    return {
        **district_summary,
        'pass': not errors,
        'errors': errors,
        'scene': special['init'][0],
        'initialization_ms': special['init'][1] / 1000,
        'surface_rectangles': special['surface'][0],
        'solid_cells_start': district_summary.get('initial_solid_cells', frame_data[0][2]),
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
        'view': view_summary,
        'edits': len(edits),
        'edit_latency': stats([int(row[2]) / 1000 for row in cuts]),
    }


def summarize_district(rows, frames, edits, edit_frames, scale, mode, warmup, measured):
    """Validate actual world scale, body motion and cache identity on every frame."""
    errors = []
    inventory = [row for row in rows if row and row[0] == 'world']
    cache_rows = [row for row in rows if row and row[0] == 'mesh_cache']
    body_rows = [row for row in rows if row and row[0] == 'bodies']
    try:
        if len(inventory) != 1 or len(inventory[0]) != 6:
            raise ValueError('expected one world inventory')
        solids, assemblies, regions, districts, budget = map(int, inventory[0][1:])
        if (solids, assemblies, regions, districts) != (2261844 * scale, 154 * scale, 3338 * scale, scale):
            raise ValueError('world inventory does not match real district scale')
        if len(cache_rows) != len(frames) or len(body_rows) != len(frames):
            raise ValueError('missing mesh cache or body samples')
        caches, bodies = [], []
        for i, (cache_row, body_row) in enumerate(zip(cache_rows, body_rows)):
            if len(cache_row) != 7 or len(body_row) != 6:
                raise ValueError('invalid mesh cache/body row width')
            cache = list(map(int, cache_row[1:]))
            body = [*map(int, body_row[1:5]), float(body_row[5])]
            if cache[0] != i or body[0] != i or any(v < 0 for v in cache + body[1:4]):
                raise ValueError('invalid mesh cache/body index or counts')
            if not math.isfinite(body[4]) or body[4] > 0:
                raise ValueError('invalid body translation')
            if body[1] + frames[i][3] != cache[2] or body[2] > frames[i][3] or body[3] > frames[i][3]:
                raise ValueError('body ownership, anchor or motion counts disagree')
            if i and i not in edit_frames and cache[1] != 0:
                errors.append(f'Unedited geometry rebuilt at frame {i}')
            if i and cache[1] > edit_frames.get(i, 0) * 2:
                errors.append(f'An edit rebuilt unrelated body geometry at frame {i}')
            if cache[3] > cache[2]:
                errors.append(f'Draw count exceeds live bodies at frame {i}')
            caches.append(cache)
            bodies.append(body)
        times = {frame[0]: i for i, frame in enumerate(frames)}
        actual_edits = Counter(times[int(edit[1])] for edit in edits)
        if actual_edits != edit_frames:
            errors.append('Edit batches do not match their scheduled frames')
        previous = solids
        for frame in frames:
            if frame[2] > previous or frame[3] > budget:
                errors.append('World gained cells or exceeded the body budget')
            previous = frame[2]
        total_edits = sum(edit_frames.values())
        if total_edits and frames[-1][2] >= solids:
            errors.append('Accepted edits did not remove real cells')
        if mode == 'bridge' and total_edits == 2:
            if frames[-1][3] != 1 or frames[-1][2] != solids - 56:
                errors.append('The second bridge fuse did not detach exactly one bridge')
        if mode == 'fragments':
            if frames[-1][3] != total_edits:
                errors.append('Support cuts did not produce the requested independent fragments')
            if measured >= 17 and max(row[2] for row in bodies) != 128 * scale:
                errors.append('Requested fragment population was not falling simultaneously')
        if mode in ('static', 'camera', 'aim') and (frames[-1][2] != solids or frames[-1][3] != 0):
            errors.append('View-only workload mutated the world')
        measured_cache = caches[warmup:]
        return {
            'initial_solid_cells': solids,
            'initial_assemblies': assemblies,
            'initial_regions': regions,
            'body_budget': budget,
            'max_moving_bodies': max(row[2] for row in bodies),
            'max_translated_bodies': max(row[3] for row in bodies),
            'minimum_body_offset_m': min(row[4] for row in bodies),
            'meshes_rebuilt': sum(row[1] for row in measured_cache),
            'upload_mib': {key.replace('_ms', '_mib'): value for key, value in
                stats([row[5] / 1048576 for row in measured_cache]).items()},
            'visible_bodies_max': max(row[3] for row in measured_cache),
        }, errors
    except (ValueError, IndexError, KeyError) as exc:
        return {}, [f'Invalid district samples: {exc}']
