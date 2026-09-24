"""Validate and summarize fixed-frame stress runs."""
import csv
import io

from benchmark_parser import STAGES, VULKAN_STAGES, parse_run, stats


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
    baseline = parse_run(io.StringIO(''.join(','.join(row) + '\n' for row in ordinary)),
                         exit_code, require_vulkan_detail=True)
    errors.extend(baseline['instrumentation_errors'])
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
