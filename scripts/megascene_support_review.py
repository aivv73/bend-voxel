"""Bind user-approved supplementary cut captures to the primary action state."""
import hashlib
from megascene_inventory import require


def review_details(archive,frozen,records,review):
    for planned in frozen['supplementary_views']:
        frame=planned['frame']
        cp=next((r for r in records if r['record_type']=='checkpoint' and r['frame']==frame),None)
        captures=[r for r in records if r['record_type']=='detail_capture' and r['rendered_frame']==frame]
        work=[r['evidence'] for r in records if r['record_type']=='detail_render' and r['rendered_frame']==frame and
              r['phase']=='closeup' and r['evidence']['record_type']=='render_work']
        path=archive/'validation'/'captures'/f'detail-{int(frame):04d}.ppm'
        available=path.is_file() and len(captures)==len(work)==1 and cp is not None
        if not available:review['missing'].append(planned['name'])
        if captures:require(captures[0]['camera']==planned['camera'],'supplementary review camera mismatch')
        view={'name':planned['name'],'frame':frame,'pose':'support_cut_closeup','camera':planned['camera'],
              'supplementary_to':planned['supplementary_to'],'checkpoint_sha256':cp['sha256'] if cp else None,
              'features':[{'name':name,'geometry':'pending','readability':'pending'} for name in planned['features']],
              'capture':{'path':path.relative_to(archive).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                         'size_bytes':str(path.stat().st_size)} if available else None,'capture_recorded':bool(captures)}
        for key in ('shadow_extent_m','shadow_texel_m','shadow_fit_min_margin_texels'):view[key]=work[0][key] if work else None
        review['views'].append(view)
        original=next(v for v in review['views'] if v['name']==planned['supplementary_to'])
        for feature in original['features']:
            if feature['name'] in planned['features']:feature['covered_by']=planned['name']
    review['status']='incomplete' if review['missing'] else 'awaiting_named_feature_review'
    review['supplementary_scope']='User-approved validation-only cut close-ups; same post-cut world, frozen cameras, no simulation or measured samples; primary overview restored.'
