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


def assess(bundle, input_path, reviewer):
    root=Path(bundle).expanduser().resolve()
    require(reviewer.strip(), "reviewer identity required")
    manifest=read_json((root/"manifest.json").read_text())
    require(manifest["effective"]["case"] in ("traversal", "picking", "localized", "support"), "traversal bundle required")
    require(manifest["attempt_kind"] in ("validation_only", "development_observation"), "complete bundle required")
    summary=read_json((root/"summary.json").read_text())
    require(summary["schedule_completion"]["status"] == "pass" and
            summary["state_correctness"]["status"] == "pass", "complete validated replay required")
    review=read_json((root/"review.json").read_text())
    require(not review["missing"], "required capture missing")
    frozen=read_json((root/"schedule.json").read_text())
    require(review["schedule_sha256"]==hashlib.sha256((root/"schedule.json").read_bytes()).hexdigest(), "stale review schedule")
    require(frozen["schedule_id"] in ("traversal-v1", "traversal-v2", "picking-v1", "picking-v2", "localized-v1", "support-v1"), "unsupported route")
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
            require(manifest['effective']['case']=='support', 'unexpected supplementary feature coverage')
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
