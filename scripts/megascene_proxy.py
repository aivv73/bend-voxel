"""Accepted proxy diagnostics: frozen routes and independent selection oracle.

The fixture and predicted decisions use source boxes, never the native cache's
group or selected flags. Native membership, metrics, draws and retained work
are checked separately during replay.
"""
import math
import struct

from megascene_inventory import SCHEMA, require
from megascene_recipe import Box, Owner, bits, f32, generate
from megascene_traversal import camera, pose
from megascene_picking import center, checked_result, ZERO

DIAGNOSTICS = ("mixed-world", "compact-reference")
HOLD_P = (105, 75, 90, 105, 90, 75, 75, 75, 105)


def owners(config):
    if config.get("diagnostic") != "compact-reference":
        return generate(config["preset"], int(config["seed"]))
    result = []
    for iz in range(2):
        for ix in range(2):
            v, ox, oz = ix + 2*iz, -272 + 40*ix, -168 + 40*iz
            boxes = [Box((x[0]+ox, y[0], z[0]+oz), (x[1]+ox, y[1], z[1]+oz), m)
                     for x,y,z,m in (
                         ((280,288),(24,26),(176,184),1),
                         ((280,288),(26,42),(176,184),4),
                         ((272,288),(42,50),(168,184),4),
                         ((280,296),(50,58+v%2),(176,192),3),
                         ((288,302+v%2),(34,50),(184,199),4))]
            result.append(Owner("irregular", ix+2*iz, boxes))
    return result


def group(source):
    require(len(source) >= 4, "proxy diagnostic requires four source owners")
    candidates = []
    for ident, owner in enumerate(source, 1):
        lo = tuple(min(b.lo[k] for b in owner.boxes) for k in range(3))
        hi = tuple(max(b.hi[k] for b in owner.boxes) for k in range(3))
        if any(hi[k]-lo[k] > 35 for k in range(3)):
            continue
        key = (math.floor(((lo[0]+hi[0])/2+320)/640),
               math.floor(((lo[2]+hi[2])/2+320)/640))
        candidates.append((ident,key,lo,hi))
    members = [item for item in candidates if item[1] == (0,0)]
    require(len(members) == 4, "expected exactly four eligible central tile members")
    lo = tuple(min(item[2][k] for item in members) for k in range(3))
    hi = tuple(max(item[3][k] for item in members) for k in range(3))
    c = tuple(f32((a+b)/20) for a,b in zip(lo,hi))
    radius = f32(math.sqrt(sum(((b-a)/20)**2 for a,b in zip(lo,hi))))
    return {"tile": ["0","0"], "members": [str(item[0]) for item in members],
            "lo_cells": list(map(str,lo)), "hi_cells": list(map(str,hi)),
            "center_m": list(map(bits,c)), "radius_m": bits(radius)}


def schedule(config, source):
    diagnostic = config["diagnostic"]
    require(diagnostic in DIAGNOSTICS, "unsupported proxy diagnostic")
    require((int(config["warmup"]),int(config["frames"])) == (120,3600), "proxy diagnostics require 120/3600 frames")
    g = group(source)
    lo, hi = [[int(x) for x in g[k]] for k in ("lo_cells","hi_cells")]
    center_m = tuple((a+b)/20 for a,b in zip(lo,hi))
    radius = math.sqrt(sum(((b-a)/20)**2 for a,b in zip(lo,hi)))
    height = int(config["resolution"].split("x")[1])
    if diagnostic == "mixed-world":
        require(config["preset"] == "small" and height == 1080, "mixed-world route requires small/1080p")
        far = camera((center_m[0],center_m[1],center_m[2]+1000), center_m)
        near = camera((center_m[0],center_m[1],center_m[2]+100), center_m)
        views = [far,near,far]
        opening = camera(*pose("opening",0,"small",int(config["seed"]),"traversal-v2"))
        hold_length = 1200
        labels = ("far_entry","near_exit","far_reentry")
    else:
        require(config["preset"] == "small", "compact reference requires small preset")
        require(all(hi[k]-lo[k] <= limit for k,limit in enumerate((71,35,71))), "compact fixture bounds changed")
        def at(p, target=center_m):
            distance = radius + 800*(height/360)*radius/p
            return camera((center_m[0],center_m[1],center_m[2]+distance),target)
        views = [at(p) for p in HOLD_P]
        opening = views[0]
        hold_length = 120
        labels = tuple(f"hold_{i}" for i in range(9))
    # Opening and all warm-up frames use the first pose. Picking is disabled
    # during warm-up, so both profiles enter measured work from the same state.
    frames = []
    boxes = [(i,b,0.) for i,owner in enumerate(source,1) for b in owner.boxes]
    rays, outcomes = {}, {}
    for index in range(3721):
        measured = index-121
        hold = 0 if measured < 0 else min(measured//hold_length,len(views)-1)
        view = opening if measured < 0 else views[hold]
        picking = config["case"] == "picking" and measured >= 0 and (diagnostic != "mixed-world" or hold != 1)
        target = None
        if picking:
            if diagnostic == "compact-reference" and hold == 6:
                distance = radius + 800*(height/360)*radius/75
                hit_view = camera((center_m[0],center_m[1],center_m[2]+distance),(6,4.2,7.1))
                ray = center(hit_view)
                forward = center(view)
                require(ray["origin_m"] == view["eye_m"] and
                        sum(number(a)*number(b) for a,b in zip(ray["direction"],forward["direction"])) > .99,
                        "reachable pointer ray lies outside declared compact view")
                target = "right_lobe"
            else:
                ray = rays.setdefault(hold, center(view))
                target = "declared_miss"
            ray_key = tuple(ray["origin_m"]+ray["direction"])
            if ray_key not in outcomes:
                outcomes[ray_key] = checked_result(boxes,ray)
            expected, reference = outcomes[ray_key]
            if target == "right_lobe":
                require((expected["owner"],expected["material"],expected["kind"]) == ("4","4","1") and
                        reference["distance"] < 256, "reachable right-lobe target changed")
            else:
                require(expected["kind"] == "0", "declared top-center miss changed")
        else:
            ray = None
            expected = {"owner":"0","material":"0","kind":"0","distance_m":ZERO,"position_m":[ZERO]*3}
        frames.append({"frame":str(index), "phase":"startup" if index==0 else "warmup" if index<=120 else "ordinary",
                       "measured_ordinal":str(measured) if measured>=0 else None,
                       "route_phase":labels[hold] if measured>=0 else None,
                       "phase_offset":str(measured%hold_length) if measured>=0 else None,
                       "camera":view,"picking":picking,"ray":ray,"expected_pick":expected,
                       "target":target,"actions":[]})
    reviews = [{"name":"opening","frame":"0","features":["full source geometry","major shadows"]}]
    checkpoints = [{"name":"initialization","frame":"0"},{"name":"review_opening","frame":"0"},
                   {"name":"warmup_end","frame":"120"}]
    for i,label in enumerate(labels):
        frame = str(121+i*hold_length+hold_length//2)
        reviews.append({"name":"review_"+label,"frame":frame,"pose":label,
                        "features":["group silhouette","major shadows"]})
        checkpoints.append({"name":"review_"+label,"frame":frame})
    reviews.append({"name":"completion","frame":"3720","features":["unchanged geometry","major shadows"]})
    checkpoints.append({"name":"completion","frame":"3720"})
    enabled_count=sum(f["picking"] for f in frames)
    hit_count=sum(f["picking"] and f["expected_pick"]["kind"] != "0" for f in frames)
    from megascene_supplementary import proxy_views
    return {"schema":SCHEMA,"record_type":"schedule","fixed_step":"0x3c888889",
            "schedule_id":f"proxy-{diagnostic}-{config['case']}-v1", "diagnostic":diagnostic,
            "warmup_frames":"120","measured_frames":"3600","opening":opening,
            "frames":frames,"actions":[],"review_views":reviews,"required_checkpoints":checkpoints,
            "supplementary_views":proxy_views(source, reviews),
            "group_reference":g,"hold_length":str(hold_length),"hold_labels":list(labels),
            "picking_admission":{"status":"pass","enabled_samples":str(enabled_count),
                "required_hits":str(hit_count),"required_misses":str(enabled_count-hit_count),
                "reach_m":"256","reach_comparison":"strictly_less",
                "reference":"rational face intersections against source geometry",
                "runtime_guard":"actual tree bounds and F32 operations before unsafe picking"},
            "checkpoint_implementation":"megascene-checkpoint/1",
            "update_order":["physics","edit_disabled","view_picking" if config["case"]=="picking" else "view_picking_disabled","render"]}


def number(word):
    return struct.unpack(">f",bytes.fromhex(word[2:]))[0]


def audit(records, frozen, config):
    """Check native membership and decisions against source bounds and frozen aim."""
    group_ref = frozen["group_reference"]
    lo = [int(x) for x in group_ref["lo_cells"]]
    hi = [int(x) for x in group_ref["hi_cells"]]
    c = [(a+b)/20 for a,b in zip(lo,hi)]
    radius = math.sqrt(sum(((b-a)/20)**2 for a,b in zip(lo,hi)))
    height = int(config["resolution"].split("x")[1])
    native = [r for r in records if r["record_type"] == "native_audit"]
    work = [r for r in records if r["record_type"] == "render_work"]
    require(len(native) == len(work) == len(frozen["frames"]), "missing proxy native/work samples")
    previous = False
    holds = {}
    for n,w,frame in zip(native,work,frozen["frames"]):
        index = frame["frame"]
        require(n["frame"] == w["frame"] == index, "proxy evidence frame order mismatch")
        groups = n["proxy_group_evidence"]
        require(set(groups) == {"0"} and w["proxy_groups"] == "1", "proxy tile group membership changed")
        g = groups["0"]
        require(g["members"] == group_ref["members"], "proxy member identities changed")
        view = frame["camera"]
        eye = [number(x) for x in view["eye_m"]]
        yaw,pitch = number(view["yaw"]),number(view["pitch"])
        forward = (math.sin(yaw)*math.cos(pitch),math.sin(pitch),math.cos(yaw)*math.cos(pitch))
        depth = sum((c[k]-eye[k])*forward[k] for k in range(3))-radius
        metric = math.inf if depth <= .05 else 800*(height/360)*radius/depth
        measured = number(g["metric_bits"])
        require((math.isinf(metric) and math.isinf(measured)) or
                (math.isfinite(measured) and abs(measured-metric) < .03),
                "native render-pixel metric differs from source bounds")
        aim = frame["expected_pick"]
        suppressed = aim["kind"] != "0" and all(lo[k]-2 <= number(aim["position_m"][k])*10 <= hi[k]+2 for k in range(3))
        require(g["aim_suppressed"] is suppressed, "native aim suppression disagrees with reachable pick")
        selected = metric < (100 if previous else 80) and not suppressed
        require(g["selected"] is selected, "wrong 80/100 hysteresis selection at frame "+index)
        require(n["selected_ids"] == (group_ref["members"] if selected else []), "selected body membership mismatch")
        if config["profile"] == "full":
            require(w["proxy_draws"] == "0" and not n["proxied_ids"], "full profile substituted proxy geometry")
        else:
            require(selected or not n["proxied_ids"], "unselected proxy group drew bodies")
            require(int(w["proxied_bodies"]) == len(n["proxied_ids"]), "proxied body count mismatch")
            require(int(w["proxy_draws"]) == int(bool(n["proxied_ids"])), "proxy draw count mismatch")
        require(int(w["full_vertices"]) > 0 and int(w["proxy_vertices"]) > 0 and
                int(w["resident_vertex_bytes"]) >= 0, "retained geometry/storage missing")
        require(int(w["full_meshes"]) == (4 if config["diagnostic"] == "compact-reference" else 21), "full body meshes not resident")
        require(w["shadow_body_draws"] == (w["body_count"] if index == "0" else "0"), "full shadow draw cache changed")
        previous = selected
        if (frame["route_phase"] and frame["route_phase"] not in holds and
                frame["phase_offset"] == str(int(frozen["hold_length"])//2)):
            holds[frame["route_phase"]] = {"frame":index,"metric_px":g["metric_bits"],
                "entry_margin_px":metric-80,"exit_margin_px":metric-100,
                "selected":selected,"aim_suppressed":suppressed,
                "selected_bodies":n["selected_ids"],"proxied_bodies":n["proxied_ids"],
                "main_body_draws":w["main_body_draws"],"proxy_draws":w["proxy_draws"],
                "full_vertices":w["full_vertices"],"proxy_vertices":w["proxy_vertices"],
                "resident_vertex_bytes":w["resident_vertex_bytes"],"uploaded_bytes":w["uploaded_bytes"],
                "mesh_rebuilt":w["mesh_rebuilt"],"proxy_rebuilt":w["proxy_rebuilt"],
                "shadow_body_draws":w["shadow_body_draws"],"shadow_extent_m":w["shadow_extent_m"],
                "shadow_texel_m":w["shadow_texel_m"],"shadow_fit_min_margin_texels":w["shadow_fit_min_margin_texels"]}
    require(set(holds) == set(frozen["hold_labels"]), "missing proxy hold midpoint evidence")
    if config["diagnostic"] == "compact-reference":
        expected = [False,True,True,False,False,True,config["case"] != "picking",True,False]
        for i,choice in enumerate(expected):
            require(holds[f"hold_{i}"]["selected"] is choice, "wrong compact hysteresis fixture")
        require(holds["hold_6"]["aim_suppressed"] is (config["case"] == "picking"), "reachable aim suppression missing")
    else:
        require([holds[name]["selected"] for name in frozen["hold_labels"]] == [True,False,True], "mixed-world entry/exit/reentry mismatch")
    return {"status":"pass","scope":"actual native group, source-bound metric, 80/100 selection and retained work",
            "group":group_ref,"holds":holds}


def pair(full_path, proxy_path):
    """Read two completed bundles; never turn missing evidence into a pass."""
    from pathlib import Path
    import hashlib
    from megascene_inventory import read_json
    from megascene_checkpoints import identity, verify_evidence

    bundles = []
    for location, profile in ((full_path,"full"),(proxy_path,"proxy")):
        root = Path(location).expanduser().resolve()
        manifest = read_json((root/"manifest.json").read_text())
        config = manifest["effective"]
        require(config["profile"] == profile and config["diagnostic"] in DIAGNOSTICS,
                "paired bundle profile/diagnostic mismatch")
        require(manifest["synthetic"] is False, "synthetic bundle cannot establish paired execution")
        identity(manifest,root,config)
        verify_evidence(manifest,root,("summary.json","validation.json","comparison.json","review.json",
                                       "inputs.json","schedule.json","supervision.json","cpu.jsonl",
                                       "validation/comparison.json","validation/cpu.jsonl"))
        summary = read_json((root/"summary.json").read_text())
        validation = read_json((root/"validation.json").read_text())
        review = read_json((root/"review.json").read_text())
        comparison = read_json((root/"comparison.json").read_text())
        require(summary["attempt_kind"] == "development_observation" and
                all(summary[key]["status"] == "pass" for key in ("schedule_completion","state_correctness","rendering_correctness")) and
                summary["proxy_diagnostic"]["status"] == "pass" and
                validation["status"] == comparison["status"] == "pass" and
                review["profile"] == profile and not review["missing"],
                "paired run or validation/captures incomplete")
        for view in review["views"]:
            capture=view["capture"]
            require(capture is not None, "missing midpoint capture")
            path=root/capture["path"]
            require(path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest()==capture["sha256"],
                    "stale midpoint capture")
        records=[read_json(line) for line in (root/"cpu.jsonl").read_text().splitlines()]
        work=[r for r in records if r["record_type"] == "render_work"]
        require(len(work)==3721,"incomplete paired render work")
        supervision=read_json((root/"supervision.json").read_text())
        require(supervision["allocation_ledger"]["scope"] == "explicit Vulkan allocations; not residency or heap budgets",
                "unknown Vulkan storage scope")
        costs={"uploaded_bytes":str(sum(int(r["uploaded_bytes"]) for r in work)),
               "mesh_rebuilds":str(sum(int(r["mesh_rebuilt"]) for r in work)),
               "proxy_rebuilds":str(sum(int(r["proxy_rebuilt"]) for r in work)),
               "shadow_refresh_body_draws":str(sum(int(r["shadow_body_draws"]) for r in work)),
               "resident_full_shadow_meshes":work[-1]["body_count"],
               "max_cpu_vertex_arena_bytes":str(max(int(r["resident_vertex_bytes"]) for r in work)),
               "peak_explicit_vulkan_allocation_bytes":supervision["allocation_ledger"]["peak_bytes"],
               "peak_process_rss_bytes":supervision["observed_maxima"]["rss_bytes"],
               "full_mesh_vertices":work[-1]["full_vertices"],"proxy_vertices":work[-1]["proxy_vertices"]}
        bundles.append((root,manifest,config,summary,validation,review,comparison,costs))
    a,b=bundles
    same={k:a[2][k]==b[2][k] for k in ("case","diagnostic","preset","seed","threads","resolution",
                                            "fragment_budget","warmup","frames","schedule")}
    require(all(same.values()),"paired configuration differs beyond profile")
    for runtime_path in ("runtime/worker","runtime/build/libvoxel_vulkan.so",
                         "runtime/build/vulkan-scene.frag.spv","runtime/build/vulkan-scene.vert.spv",
                         "runtime/build/vulkan-shadow.vert.spv"):
        hashes=({entry["path"]:entry["sha256"] for entry in bundle[1]["artifacts"]}
                for bundle in (a,b))
        left,right=hashes
        require(left.get(runtime_path) is not None and left[runtime_path]==right.get(runtime_path),
                "paired compiled renderer/worker artifacts differ: "+runtime_path)
    require(hashlib.sha256((a[0]/"schedule.json").read_bytes()).digest()==
            hashlib.sha256((b[0]/"schedule.json").read_bytes()).digest(),"paired camera/aim/action histories differ")
    require(hashlib.sha256((a[0]/"inputs.json").read_bytes()).digest()==
            hashlib.sha256((b[0]/"inputs.json").read_bytes()).digest(),"paired source world differs")
    require(a[4]["checkpoints"]==b[4]["checkpoints"] and a[4]["expected"]==b[4]["expected"] and
            a[4]["actual_work"]==b[4]["actual_work"],"paired world/geometry checkpoints differ")
    if a[2]["case"]=="picking":
        require(a[4]["picking"]==b[4]["picking"],"paired picking differs")
    ah,bh=a[3]["proxy_diagnostic"]["holds"],b[3]["proxy_diagnostic"]["holds"]
    require(set(ah)==set(bh),"paired hold midpoint mismatch")
    for name in ah:
        require(all(ah[name][key]==bh[name][key] for key in
                    ("frame","metric_px","selected","aim_suppressed","selected_bodies",
                     "shadow_extent_m","shadow_texel_m","shadow_fit_min_margin_texels","shadow_body_draws")),
                "paired metric/selection/shadow semantics differ at "+name)
        require(ah[name]["proxy_draws"]=="0", "full pair substituted proxies")
    return {"schema":SCHEMA,"record_type":"proxy_pair","status":"pass",
            "case":a[2]["case"],"diagnostic":a[2]["diagnostic"],
            "bundles":{"full":str(a[0]),"proxy":str(b[0])},
            "group":a[3]["proxy_diagnostic"]["group"],
            "holds":{name:{"full":ah[name],"proxy":bh[name]} for name in ah},
            "costs":{"full":a[7],"proxy":b[7],
                     "upload_scope":"bytes copied into the mapped native vertex arena across all 3,721 frames; includes dirty geometry and dynamic overlays",
                     "storage_scope":"CPU native vertex arena capacity, explicit Vulkan allocation peak, and process-tree RSS peak; none is resident world cell storage alone"},
            "captures":{"full":[v["capture"] for v in a[5]["views"]],
                        "proxy":[v["capture"] for v in b[5]["views"]]},
            "allowed_appearance_differences":["selected eligible bodies use material-colored box proxies in the main pass",
                                              "surface detail and silhouettes can differ at selected holds"],
            "unchanged_semantics":["source world","physics and warm-up","camera/aim history","picking",
                                   "canonical world/geometry checkpoints","full-mesh shadow fit and draws"],
            "performance_qualification":{"status":"inconclusive","reason":"applicable instrumentation calibration is required for performance claims"}}


if __name__ == "__main__":
    import argparse
    from pathlib import Path
    from megascene import snapshot
    parser=argparse.ArgumentParser(description="Compare completed full/proxy diagnostic bundles")
    parser.add_argument("--pair",nargs=2,required=True,metavar=("FULL","PROXY"))
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    output=Path(args.output)
    require(not output.exists(),"pair output already exists")
    try:
        result=pair(*args.pair)
    except (ValueError,KeyError,TypeError,OSError) as exc:
        result={"schema":SCHEMA,"record_type":"proxy_pair","status":"inconclusive",
                "reason":str(exc),"bundles":{"full":args.pair[0],"proxy":args.pair[1]},
                "performance_qualification":{"status":"inconclusive","reason":"paired evidence incomplete or invalid"}}
    snapshot(output,result)
    print(output)
    raise SystemExit(0 if result["status"]=="pass" else 2)
