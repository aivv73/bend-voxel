#!/usr/bin/env python3
"""Record named traversal feature assessments against immutable captures."""
import argparse
from datetime import datetime, timezone
import hashlib
from pathlib import Path
import struct

from megascene import artifact, snapshot
from megascene_inventory import outcome, read_json, require


def finite_bit_float(value):
    require(isinstance(value,str) and len(value)==10 and value.startswith("0x"), "missing binary32 shadow evidence")
    number=struct.unpack(">f",bytes.fromhex(value[2:]))[0]
    require(number == number and abs(number) < float("inf"), "nonfinite shadow evidence")
    return number


def assess_static(root, manifest, input_path, reviewer):
    """Assess the separately captured static opening without changing timed work."""
    require(manifest.get("synthetic") is False and manifest["attempt_kind"] == "development_observation",
            "real timed static attempt required")
    summary=read_json((root/"summary.json").read_text())
    require(summary["schedule_completion"]["status"] == "pass" and
            summary["state_correctness"]["status"] == "pass" and
            summary["opening_capture"]["status"] == "pass", "complete validated static capture required")
    review=read_json((root/"review.json").read_text())
    frozen=read_json((root/"schedule.json").read_text())
    require(review["schedule_sha256"]==hashlib.sha256((root/"schedule.json").read_bytes()).hexdigest() and
            review["view"] == "opening", "stale opening review schedule")
    capture=review["capture"]
    require(capture is not None and (root/capture["path"]).is_file() and
            artifact(root/capture["path"],root)==capture, "opening capture missing or changed")
    required=frozen["review_views"]
    require(len(required)==1 and required[0]["name"]=="opening", "unexpected static review views")
    answers=read_json(Path(input_path).read_text())
    require(answers["schema"]=="megascene-feature-assessments/1" and
            isinstance(answers["views"],dict) and set(answers["views"])=={"opening"},
            "opening assessment missing")
    selected=answers["views"]["opening"]
    require(isinstance(selected,dict) and set(selected)==set(required[0]["features"]),
            "every opening feature needs assessment")
    bad_geometry=[];bad_quality=[]
    for name in required[0]["features"]:
        answer=selected[name]
        require(answer["geometry"] in ("correct","incorrect") and
                answer["readability"] in ("readable","insufficient","unassessable"),
                "invalid opening feature classification")
        require(answer["geometry"]=="correct" or answer["readability"]=="unassessable",
                "incorrect geometry cannot receive readability pass")
        if answer["geometry"]!="correct" or answer["readability"]!="readable":
            require(isinstance(answer.get("note"),str) and answer["note"].strip(),
                    "nonpassing opening feature needs an explanation")
        if answer["geometry"]=="incorrect": bad_geometry.append(name)
        elif answer["readability"]!="readable": bad_quality.append(name)
    raw=root/"assessments.json"
    require(not raw.exists(), "assessments already recorded")
    review.update(status="incorrect_rendering" if bad_geometry else
                  "insufficient_readability" if bad_quality else "pass",
                  reviewer=reviewer,reviewed_at_utc=datetime.now(timezone.utc).isoformat(),
                  features=selected,incorrect_geometry_features=bad_geometry,
                  insufficient_readability_features=bad_quality)
    snapshot(raw,answers)
    review["assessment_input"]=artifact(raw,root)
    snapshot(root/"review.json",review)
    if bad_geometry:
        summary["rendering_correctness"]=outcome("fail","opening geometry incorrect","static full profile",["review.json","assessments.json"])
        summary["visual_quality"]=outcome("inconclusive","opening geometry incorrect","static full profile",["review.json","assessments.json"])
    else:
        summary["visual_quality"]=outcome("fail" if bad_quality else "pass",
            "opening feature unreadable" if bad_quality else "all opening features visible and readable",
            "static full profile",["review.json","assessments.json"])
    summary["review"]={"path":"review.json","status":review["status"],"reviewer":reviewer}
    snapshot(root/"summary.json",summary)
    if (root/"cpu.jsonl").is_file():
        from megascene_report import report_bundle
        snapshot(root/"summary.json",report_bundle(root))
    manifest["evidence"]=[item for item in manifest["evidence"] if item["path"] not in
                          ("review.json","summary.json","assessments.json")]
    manifest["evidence"] += [artifact(root/name,root) for name in ("review.json","summary.json","assessments.json")]
    manifest["evidence"].sort(key=lambda item:item["path"])
    snapshot(root/"manifest.json",manifest)
    return review["status"]


def assess(bundle, input_path, reviewer):
    root=Path(bundle).expanduser().resolve()
    require(reviewer.strip(), "reviewer identity required")
    manifest=read_json((root/"manifest.json").read_text())
    from megascene_performance import enabled, admit, validate
    performance=enabled(manifest['effective'])
    if manifest["effective"]["case"] == "static" and not performance:
        return assess_static(root,manifest,input_path,reviewer)
    require(performance or manifest["effective"]["case"] in ("traversal", "picking", "localized", "support", "history"), "replay bundle required")
    if performance:
        admit(manifest['effective'])
        require(manifest.get('synthetic') is False, 'real performance replay required')
    off_validation=(performance and manifest['attempt_kind']=='calibration_off' and
                    manifest['effective'].get('validation_only') is True)
    require(off_validation or manifest["attempt_kind"] in ("validation_only", "development_observation", "calibration_on"),
            "complete bundle required")
    summary=read_json((root/"summary.json").read_text())
    require(not off_validation or summary.get('attempt_kind')=='validation_only', 'off validation summary required')
    require(summary["schedule_completion"]["status"] == "pass" and
            summary["state_correctness"]["status"] == "pass", "complete validated replay required")
    review=read_json((root/"review.json").read_text())
    require(not review["missing"], "required capture missing")
    frozen=read_json((root/"schedule.json").read_text())
    if performance:
        validate(frozen)
        require(frozen['schedule_id']==manifest['effective']['schedule'], 'review schedule identity mismatch')
    require(review["schedule_sha256"]==hashlib.sha256((root/"schedule.json").read_bytes()).hexdigest(), "stale review schedule")
    require(frozen["schedule_id"] in ("traversal-v1", "traversal-v2", "picking-v1", "picking-v2", "localized-v1", "support-v1", "history-v1",
                                       "fill-support-v1", "fill-history-v1", "body-rich-history-v1",
                                       "material-detail-localized-v1", "history-12-v1", "history-48-v1",
                                       "support-1-span-v1", "support-2-span-v1", "static-perf-v2", "history-perf-v2") or
            frozen["schedule_id"].startswith("proxy-"), "unsupported route")
    answers=read_json(Path(input_path).read_text())
    require(answers["schema"]=="megascene-feature-assessments/1" and isinstance(answers["views"],dict), "unsupported assessments")
    require(set(answers["views"])=={v["name"] for v in review["views"]}, "every named view needs assessment")
    bad_geometry=[]; bad_quality=[]
    for view in review["views"]:
        capture=view["capture"]
        require(capture is not None, "required capture missing")
        path=root/capture["path"]
        require(path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest()==capture["sha256"], "stale capture: "+view["name"])
        require(all(finite_bit_float(n)>0 for n in view["shadow_texel_m"]), "invalid shadow texel coverage")
        require(finite_bit_float(view["shadow_fit_min_margin_texels"])>=0, "occupied geometry outside shadow map")
        chosen=answers["views"][view["name"]]
        require(isinstance(chosen,dict) and set(chosen)=={f["name"] for f in view["features"]}, "every named feature needs assessment: "+view["name"])
        for feature in view["features"]:
            answer=chosen[feature["name"]]
            require(answer["geometry"] in ("correct", "incorrect") and answer["readability"] in ("readable", "insufficient", "unassessable"), "invalid feature classification")
            require(answer["geometry"]=="correct" or answer["readability"]=="unassessable", "incorrect geometry cannot receive readability pass")
            if answer["geometry"]!="correct" or answer["readability"]!="readable":
                require(isinstance(answer.get("note"),str) and answer["note"].strip(), "nonpassing feature needs an explanation")
            feature.update(answer)
            key=view["name"]+"/"+feature["name"]
            if answer["geometry"]=="incorrect": bad_geometry.append(key)
            elif answer["readability"]!="readable": bad_quality.append(key)
    # Preserve an occluded overview's assessment. Only its explicitly bound,
    # independently assessed close-up can supply that same feature's readability.
    covered=[]
    for view in review['views']:
        for feature in view['features']:
            if 'covered_by' not in feature: continue
            config=manifest['effective']
            planned=next((v for v in frozen.get('supplementary_views',[]) if v['name']==feature['covered_by']),None)
            allowed=config['case']=='support' or (planned is not None and (
                config['case']=='history' and planned.get('purpose')=='history_face' and
                    feature['name'] in ('removed material','new exposed surfaces') or
                config['case'] in ('traversal','picking') and
                    config.get('diagnostic') in ('mixed-world','compact-reference') and
                    planned.get('purpose')=='proxy_shadow' and feature['name']=='major shadows'))
            require(allowed, 'unexpected supplementary feature coverage')
            detail=next((v for v in review['views'] if v['name']==feature['covered_by']),None)
            require(detail is not None and detail.get('supplementary_to')==view['name'] and detail['frame']==view['frame'],
                    'supplementary feature does not cover the same action state')
            target=next((f for f in detail['features'] if f['name']==feature['name']),None)
            require(target is not None, 'supplementary feature missing')
            key=view['name']+'/'+feature['name']
            if feature['geometry']=='correct' and target['geometry']=='correct' and target['readability']=='readable' and key in bad_quality:
                bad_quality.remove(key);covered.append({'feature':key,'covered_by':detail['name']})
    if covered: review['supplementary_coverage']=covered
    review["reviewer"]=reviewer
    review["reviewed_at_utc"]=datetime.now(timezone.utc).isoformat()
    review["status"]="incorrect_rendering" if bad_geometry else "insufficient_readability" if bad_quality else "pass"
    review["incorrect_geometry_features"]=bad_geometry
    review["insufficient_readability_features"]=bad_quality
    raw=root/"assessments.json"
    require(not raw.exists(), "assessments already recorded")
    snapshot(raw,answers)
    review["assessment_input"]=artifact(raw,root)
    snapshot(root/"review.json",review)
    if bad_geometry:
        summary["rendering_correctness"]=outcome("fail","named feature rendering incorrect", "primary full-profile fidelity",["review.json","assessments.json"])
        summary["visual_quality"]=outcome("inconclusive","rendering incorrect; readability cannot qualify", "primary full-profile fidelity",["review.json"])
    else:
        summary["visual_quality"]=outcome("fail" if bad_quality else "pass",
            "required major feature unreadable" if bad_quality else "all named features visible and readable",
            "primary full-profile fidelity",["review.json","assessments.json"])
    summary["review"]={"path":"review.json","status":review["status"],"reviewer":reviewer}
    snapshot(root/"summary.json",summary)
    # Lightweight review fixtures have no retained attempt streams. A real
    # attempt always has both a versioned manifest and committed CPU evidence.
    if manifest.get("schema") == "megascene-evidence/1" and (root/"cpu.jsonl").is_file():
        from megascene_report import report_bundle
        snapshot(root/"summary.json",report_bundle(root))
    manifest["evidence"]=[artifact(root/item["path"],root) for item in manifest["evidence"]
                          if item["path"] not in ("review.json","summary.json","assessments.json")]
    manifest["evidence"] += [artifact(root/name,root) for name in ("review.json","summary.json","assessments.json")]
    manifest["evidence"].sort(key=lambda item:item["path"])
    snapshot(root/"manifest.json",manifest)
    return review["status"]


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle",required=True)
    parser.add_argument("--assessments",required=True)
    parser.add_argument("--reviewer",required=True)
    args=parser.parse_args()
    print(assess(args.bundle,args.assessments,args.reviewer))
