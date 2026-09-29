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
from megascene_recipe import generate, volume, connected
from megascene_static import audit_observation, schedule
from megascene_compare_controls import compare
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
        for control,case in (("spread","localized"),("surface-detail","localized")):
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
                    "generation_envelope_cells":{"lo":["-320","0","-320"]},
                    "occupied_bounds_cells":{"lo":["-320","0","-320"]},
                    "bodies":{"initial_owners":"21"}}
        control=copy.deepcopy(baseline)
        control.update(cells="10549440",protected_cells="415808",cuboids="210",
                       surface_rectangles="1232",exposed_area_cell_faces="1523660",vertices="7392",
                       generation_envelope_cells={"lo":["-480","0","-480"]})
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
