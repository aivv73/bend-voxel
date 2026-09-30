"""Independent source and synthetic evidence checks for terrain pressure cases."""

from itertools import product
from pathlib import Path
from unittest.mock import patch
import copy
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from megascene import configuration, parser
from megascene_recipe import generate, admit_sources
from megascene_inventory import connected, volume
from megascene_static import audit_observation, schedule
from megascene_compare_controls import compare
from megascene_inventory import surface_reference
from megascene_picking import value, exact_pick
from megascene_traversal import pose
from megascene_support import ray_to, motion
from test_megascene_static import fixtures


def material_at(boxes, point):
    hits = [b.material for b in boxes if all(b.lo[k] <= point[k] < b.hi[k] for k in range(3))]
    if len(hits) > 1:
        raise AssertionError("overlapping authored cells")
    return hits[0] if hits else None


class TerrainControls(unittest.TestCase):
    def config(self, name, case="static"):
        return configuration(parser().parse_args([
            "--case", case, "--diagnostic", name, "--output", "/tmp/control-output",
            "--archive", "/home/aivv/control-archive"]))

    def test_spread_real_connectors_and_translated_structures(self):
        base, spread = generate("small", 45), generate("small", 45, "spread")
        self.assertEqual(len(spread), 21)
        self.assertTrue(connected(spread[0].boxes))
        self.assertEqual(sum(map(volume, spread[0].boxes))-sum(map(volume, base[0].boxes)), 3*320*2*24)
        self.assertEqual(len(spread[0].boxes)-len(base[0].boxes), 6)
        for n in range(4):
            ix, iz = n%2, n//2
            shift = (320*ix-160, 0, 320*iz-160)
            for role in range(1, 6):
                before, after = base[1+5*n+role-1], spread[1+5*n+role-1]
                self.assertEqual(before.role, after.role)
                self.assertEqual([(tuple(b.lo[k]+shift[k] for k in range(3)),
                                   tuple(b.hi[k]+shift[k] for k in range(3)), b.material) for b in before.boxes],
                                 [(b.lo,b.hi,b.material) for b in after.boxes])
        terrain = spread[0].boxes
        for x,z in ((0,-321),(-321,0)):
            self.assertEqual(material_at(terrain,(x,0,z)),1)
            self.assertEqual(material_at(terrain,(x,12,z)),2)
        self.assertIsNone(material_at(terrain,(0,12,-400)))
        self.assertEqual(self.config("spread")["envelope_side_m"],"96")

    def test_material_bands_keep_occupancy_and_protected_cells(self):
        base, detail = generate("small",45), generate("small",45,"material-detail")
        self.assertEqual(len(detail),len(base))
        self.assertTrue(connected(detail[0].boxes))
        # Each removable cell uses local X bands. The protected floor remains 1.
        for n in range(4):
            ox,oz = 320*(n%2)-320,320*(n//2)-320
            for x in range(0,320):
                for y,z in ((1,4),(12,40),(23,20)):
                    before = material_at(base[0].boxes,(ox+x,y,oz+z))
                    after = material_at(detail[0].boxes,(ox+x,y,oz+z))
                    self.assertEqual(after, 2 if before == 2 and (x//4)%2 == 0 else
                                     5 if before == 2 else before)
            self.assertEqual(material_at(detail[0].boxes,(ox+100,0,oz+100)),1)
        self.assertEqual(sum(map(volume,base[0].boxes)),sum(map(volume,detail[0].boxes)))
        self.assertEqual([[(b.lo,b.hi,b.material) for b in o.boxes] for o in base[1:]],
                         [[(b.lo,b.hi,b.material) for b in o.boxes] for o in detail[1:]])

    def test_pits_exact_removed_cells_and_connectivity(self):
        base, detail = generate("small",45), generate("small",45,"surface-detail")
        self.assertEqual(len(detail),len(base))
        self.assertTrue(connected(detail[0].boxes))
        self.assertEqual(sum(map(volume,base[0].boxes))-sum(map(volume,detail[0].boxes)),4*512)
        for n in range(4):
            ox,oz = 320*(n%2)-320,320*(n//2)-320
            for u,w in product(range(8),repeat=2):
                x,z=ox+224+6*u,oz+16+6*w
                for dx,dy,dz in product(range(2),repeat=3):
                    self.assertEqual(material_at(base[0].boxes,(x+dx,22+dy,z+dz)),2)
                    self.assertIsNone(material_at(detail[0].boxes,(x+dx,22+dy,z+dz)))
                self.assertEqual(material_at(detail[0].boxes,(x+2,23,z)),2)
                self.assertEqual(material_at(detail[0].boxes,(x,21,z)),2)
            self.assertEqual(material_at(detail[0].boxes,(ox+100,0,oz+100)),1)
        self.assertEqual([[(b.lo,b.hi,b.material) for b in o.boxes] for o in base[1:]],
                         [[(b.lo,b.hi,b.material) for b in o.boxes] for o in detail[1:]])

    def test_fill_reference_layers_cavity_and_shifted_targets(self):
        base, filled = generate("small",45), generate("small",45,"fill")
        self.assertEqual(len(filled),21)
        self.assertEqual(admit_sources(filled,320,2048)["cells"],"13780160")
        for n in range(4):
            ox,oz=320*(n%2)-320,320*(n//2)-320
            terrain=filled[0].boxes
            for y,material in ((0,1),(7,2),(8,2),(15,2),(16,2),(31,2),(32,None)):
                self.assertEqual(material_at(terrain,(ox+100,y,oz+100)),material)
            for y,material in ((7,2),(8,2),(15,2),(16,None),(30,None),(31,None),(32,None)):
                self.assertEqual(material_at(terrain,(ox+250,y,oz+250)),material)
            self.assertEqual(material_at(terrain,(ox+250,30,oz+272)),2)
            for offset in (0,1,2,3):
                self.assertEqual(material_at(filled[1+5*n].boxes,(ox+18,24+offset,oz+18)),None)
            self.assertEqual(material_at(filled[1+5*n].boxes,(ox+18,32,oz+18)),1)
        for case in ("support","history"):
            base_schedule=schedule(self.config_base(case))
            control=schedule(self.config("fill",case))
            self.assertEqual(control["schedule_id"],"fill-"+case+"-v1")
            self.assertEqual(len(control["actions"]),len(base_schedule["actions"]))
            for old,new in zip(base_schedule["actions"],control["actions"]):
                self.assertEqual(old["frame"],new["frame"])
                self.assertEqual(old["expected_removed_cells"],new["expected_removed_cells"])
                self.assertAlmostEqual(value(new["target_m"][1])-value(old["target_m"][1]),.8,places=5)
                self.assertEqual(old["reference_removed_cells"],
                    [[cell[0],str(int(cell[1])-8),cell[2],cell[3]] for cell in new["reference_removed_cells"]])
            self.assertAlmostEqual(value(control["opening"]["eye_m"][1])-value(base_schedule["opening"]["eye_m"][1]),.8,places=5)
            self.assertEqual(len(control["frames"]),3721)
        self.assertEqual(schedule(self.config("fill","support"))["released_bottom_cells"],"50")
        self.assertEqual(value(motion(100,50)[0]),-5.)

    def test_body_rich_reference_gap_owners_and_back_wall_actions(self):
        base,rich=generate("small",45),generate("small",45,"body-rich")
        self.assertEqual(len(rich),25)
        self.assertEqual(admit_sources(rich,320,2048)["cells"],"10427328")
        self.assertEqual(sum(map(volume,base[0].boxes)),sum(map(volume,rich[0].boxes)))
        for n in range(4):
            ox,oz=320*(n%2)-320,320*(n//2)-320
            left,right=rich[1+6*n:3+6*n]
            self.assertEqual((left.role,right.role),("building_left","building_right"))
            self.assertTrue(connected(left.boxes) and connected(right.boxes))
            self.assertEqual(material_at(left.boxes,(ox+18,24,oz+18)),1)
            self.assertEqual(material_at(right.boxes,(ox+130,24,oz+18)),1)
            for owner in (left,right):
                self.assertIsNone(material_at(owner.boxes,(ox+76,48,oz+54)))
            self.assertIn((1,ox+72),surface_reference(left.boxes))
            self.assertIn((0,ox+80),surface_reference(right.boxes))
            self.assertEqual(material_at(left.boxes,(ox+40,48,oz+134)),5)
        frozen=schedule(self.config("body-rich","history"))
        self.assertEqual(len(frozen["actions"]),120)
        for action in frozen["actions"][6::10]:
            self.assertEqual(int(action["expected_removed_cells"])>0,True)
            self.assertEqual(action["pre_edit_hit"]["material"],"5")
            self.assertAlmostEqual(value(action["target_m"][2])-value(action["pre_edit_ray"]["origin_m"][2]),1.4,places=4)
            self.assertAlmostEqual(value(action["target_m"][0]),value(action["pre_edit_ray"]["origin_m"][0]),places=4)
        interior=pose("interior",0,"small",45,"traversal-v2","body-rich")
        self.assertEqual(interior,((-28.,4.8,-24.),(-28.,4.8,-18.8)))
        ray=ray_to(*interior)
        hit=exact_pick([(i,b,0.) for i,owner in enumerate(rich,1) for b in owner.boxes],
            interior[0],list(map(value,ray["direction"])))
        self.assertEqual((hit["owner"],hit["material"]),("2","5"))
        self.assertEqual(frozen["diagnostic_views"][0]["reference_hit"],hit)
        self.assertEqual(frozen["schedule_id"],"body-rich-history-v1")

    def config_base(self,case):
        return configuration(parser().parse_args(["--case",case,"--output","/tmp/control-output",
            "--archive","/home/aivv/control-archive"]))

    def test_frozen_identities_and_nominal_label_cannot_pass(self):
        for control, case in (("spread","static"),("material-detail","static"),
                              ("material-detail","localized"),("surface-detail","static")):
            config=self.config(control,case)
            frozen=schedule(config)
            self.assertEqual(frozen["schedule_id"],f"{control}-{case}-v1")
            self.assertEqual(len(frozen["frames"]),3721)
            if case=="localized":
                self.assertEqual(len(frozen["actions"]),1)
                self.assertEqual({int(cell[3]) for cell in frozen["reference_removed_cells"]},{2,5})
            else:
                self.assertTrue(audit_observation(fixtures(),config,[r for r in fixtures() if r["record_type"]=="frame"]))
        for control,case in (("spread","localized"),("surface-detail","localized"),
                             ("fill","static"),("body-rich","support")):
            with self.assertRaises(ValueError): self.config(control,case)
        for extra in (("--seed","46"),("--threads","1"),("--resolution","640x360"),
                      ("--warmup","1"),("--frames","2")):
            with self.assertRaises(ValueError):
                configuration(parser().parse_args(["--case","static","--diagnostic","spread",
                    "--output","/tmp/control-output","--archive","/home/aivv/control-archive",*extra]))

    def test_synthetic_comparison_requires_changed_achieved_work(self):
        baseline = {"cells":"10503360","protected_cells":"413888","cuboids":"204",
                    "surface_rectangles":"1200","exposed_area_cell_faces":"1500000","vertices":"7200",
                    "cells_by_material":{"1":"413888","2":"9388032"},
                    "exposed_area_by_material_cell_faces":{"1":"100","2":"200"},
                    "generation_envelope_cells":{"lo":["-320","0","-320"],"hi":["320","128","320"]},
                    "occupied_bounds_cells":{"lo":["-320","0","-320"],"hi":["320","86","320"]},
                    "bodies":{"initial_owners":"21"},"density":{"numerator":"10503360","denominator":"52428800"}}
        control=copy.deepcopy(baseline)
        control.update(cells="10549440",protected_cells="415808",cuboids="210",
                       surface_rectangles="1232",exposed_area_cell_faces="1523660",vertices="7392",
                       generation_envelope_cells={"lo":["-480","0","-480"]})
        control["density"]={"numerator":"10549440","denominator":"117964800"}
        control["control_comparison"]={"control":"spread",
            "baseline_source":{"cells":baseline["cells"]},"control_source":{"cells":control["cells"]}}
        common={"case":"static","preset":"small","seed":"45","threads":"6",
                "resolution":"1920x1080","profile":"full","fragment_budget":"2048",
                "warmup":"120","frames":"3600"}
        manifest=lambda ident,variant: {"attempt_id":ident,"effective":{**common,"control":variant,
                 "schedule":variant+"-static-v1" if variant else "static-v1"},
                 "worker_environment":{"MEGASCENE_SCHEDULE_SHA256":ident}}
        left=(manifest("base",None),{"attempt_id":"base-validation"},baseline)
        right=(manifest("variant","spread"),{"attempt_id":"variant-validation"},control)
        with patch("megascene_compare_controls.load",side_effect=(left,right)):
            result=compare("base","variant")
        self.assertEqual(result["delta"]["cells"],"46080")
        self.assertEqual(result["status"],"pass")
        unchanged=copy.deepcopy(control)
        unchanged.update(cells=baseline["cells"],cuboids=baseline["cuboids"],
                         surface_rectangles=baseline["surface_rectangles"])
        unchanged["control_comparison"]["control_source"]["cells"]=baseline["cells"]
        with patch("megascene_compare_controls.load",side_effect=(left,(right[0],right[1],unchanged))):
            with self.assertRaisesRegex(ValueError,"spread work mismatch"):
                compare("base","variant")

    def test_synthetic_fill_and_body_rich_comparison(self):
        base={"cells":"10503360","protected_cells":"413888","cuboids":"204",
              "surface_rectangles":"1088","exposed_area_cell_faces":"1412588","vertices":"6500",
              "cells_by_material":{"1":"413888","2":"9388032","3":"179104","4":"26208","5":"496128"},
              "exposed_area_by_material_cell_faces":{"1":"10","2":"20"},
              "generation_envelope_cells":{"lo":["-320","0","-320"],"hi":["320","128","320"]},
              "occupied_bounds_cells":{"lo":["-320","0","-320"],"hi":["320","89","320"]},
              "bodies":{"initial_owners":"21"},"density":{"numerator":"10503360","denominator":"52428800"}}
        for control,case,cells,owners in (("fill","support", "13780160","21"),
                                           ("fill","history","13780160","21"),
                                           ("body-rich","history","10427328","25")):
            changed=copy.deepcopy(base)
            changed.update(cells=cells,cuboids="208" if control=="fill" else "204",
                           surface_rectangles="1092" if control=="fill" else "1060",
                           exposed_area_cell_faces="1433068" if control=="fill" else "1374188",
                           bodies={"initial_owners":owners},
                           density={"numerator":cells,"denominator":"52428800"})
            if control=="fill":
                changed["cells_by_material"]["2"]="12664832"
                changed["occupied_bounds_cells"]["hi"][1]="97"
            changed["control_comparison"]={"control":control,
                "baseline_source":{"cells":base["cells"]},"control_source":{"cells":cells}}
            common={"case":case,"preset":"small","seed":"45","threads":"6",
                    "resolution":"1920x1080","profile":"full","fragment_budget":"2048",
                    "warmup":"120","frames":"3600"}
            manifest=lambda ident,variant: {"attempt_id":ident,"effective":{**common,"control":variant,
                "schedule":(variant+"-" if variant else "")+case+"-v1"},
                "worker_environment":{"MEGASCENE_SCHEDULE_SHA256":ident}}
            with patch("megascene_compare_controls.load",side_effect=(
                (manifest("base",None),{"attempt_id":"base-validation"},base),
                (manifest("variant",control),{"attempt_id":"variant-validation"},changed))):
                result=compare("base","variant")
            self.assertEqual(result["status"],"pass")
            self.assertEqual(result["owners"]["variant"]["initial_owners"],owners)
