"""User-approved frozen history face and proxy shadow validation views."""

from megascene_inventory import digest, require
from megascene_recipe import bits
from megascene_schedule import numeric, supplementary_bytes as camera_bytes


HISTORY_CUTS = frozenset((88, 89, 98, 99, 108, 109, 118, 119))


def history_view(action, source, created, removed):
    """Find a surviving face adjacent to removed cells, facing the cavity."""
    from megascene_picking import value
    normal = (1, 0, 0) if int(action['action']) % 10 == 8 else (-1, 0, 0)
    faces = []
    target = list(map(value, action['target_m']))
    offset = value(source.offset)
    for p in removed:
        cell = tuple(p[i] - normal[i] for i in range(3))
        for body in created:
            for box in body.boxes:
                if all(box.lo[i] <= cell[i] < box.hi[i] for i in range(3)):
                    point = [(cell[i] + .5 + normal[i] * .5) / 10 +
                             (offset if i == 1 else 0) for i in range(3)]
                    faces.append((sum((a-b)**2 for a,b in zip(point,target)),
                                  cell, box.material, point))
    require(faces, 'no independent exposed cavity face for supplementary history view')
    _, cell, material, point = min(faces)
    view = numeric("history-face", *(x.hex() for x in point), *normal)
    return {'name': 'face_' + action['action'], 'frame': action['frame'],
            'action': action['action'], 'camera': view,
            'features': ['removed material', 'new exposed surfaces'],
            'supplementary_to': 'cut_' + action['action'], 'purpose': 'history_face',
            'reference_face': {'cell': list(map(str, cell)), 'normal': list(normal),
                               'material': str(material), 'center_m': list(map(bits, point))},
            'post_cut_reference_sha256': digest([
                {'boxes': [b.record() for b in body.boxes], 'offset_m': body.offset,
                 'anchored': body.anchored} for body in created])}


def proxy_views(source, reviews):
    boxes = [box for owner in source for box in owner.boxes]
    lo = [min(b.lo[i] for b in boxes) for i in range(3)]
    hi = [max(b.hi[i] for b in boxes) for i in range(3)]
    view = numeric("proxy-shadow", *lo, *hi)
    return [{'name': 'shadow_' + r['name'], 'frame': r['frame'], 'action': None,
             'camera': view, 'features': ['major shadows'],
             'supplementary_to': r['name'], 'purpose': 'proxy_shadow',
             'source_bounds_cells': {'lo': list(map(str, lo)), 'hi': list(map(str, hi))}}
            for r in reviews if 'major shadows' in r['features']]


def audit(records, frozen, validation):
    planned = frozen.get('supplementary_views', [])
    if not planned or planned[0].get('purpose') not in ('history_face', 'proxy_shadow'):
        return
    from megascene_support import audit_details
    audit_details(records, frozen, validation)
    return {'status': 'pass', 'planned_views': str(len(planned)),
            'execution': 'same-frame validation renders with audited restoration' if validation else 'no supplementary records in timed workload',
            'invariants': ['camera/frame/action binding', 'geometry/cache identity',
                           'full-mesh shadow identity', 'restored visibility/proxy hysteresis']}


def review_details(archive, frozen, records, review):
    from megascene_support_review import review_details as bind
    bind(archive, frozen, records, review)
    for view, planned in zip(review['views'][-len(frozen['supplementary_views']):],
                             frozen['supplementary_views']):
        view['pose'] = planned['purpose']
        view['source_action'] = planned['action']
        for key in ('reference_face', 'post_cut_reference_sha256', 'source_bounds_cells'):
            if key in planned:
                view[key] = planned[key]
    review['supplementary_scope'] = ('User-approved frozen validation-only history faces or proxy shadows; '
        'same world/frame checkpoint, no simulation/actions/timed samples; original view, '
        'geometry caches, proxy hysteresis and full-mesh shadows restored.')
