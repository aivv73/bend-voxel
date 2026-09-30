import ctypes
import ctypes.util
import json
import math
from pathlib import Path
import random
import shutil
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def f32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


def bits(value):
    return "0x" + struct.pack(">f", value).hex()


def literal(value):
    return "F.Literal{" + json.dumps(float(value).hex()) + "}"


def vector(value):
    return "F.Vec{" + ",".join(map(literal, value)) + "}"


def reference_camera(eye, look):
    delta = [b-a for a, b in zip(eye, look)]
    return {"eye_m": list(map(bits, eye)), "yaw": bits(math.atan2(delta[0], delta[2])),
            "pitch": bits(math.atan2(delta[1], math.hypot(delta[0], delta[2])))}


def reference_ray(eye, look):
    delta = [b-a for a, b in zip(eye, look)]
    length = math.sqrt(sum(x*x for x in delta))
    return {"origin_m": list(map(bits, eye)), "direction": [bits(x/length) for x in delta]}


def reference_center(camera):
    libm = ctypes.CDLL(ctypes.util.find_library("m"))
    def unary(name, value):
        fn = getattr(libm, name)
        fn.argtypes = [ctypes.c_float]
        fn.restype = ctypes.c_float
        return fn(value)
    yaw, pitch = [struct.unpack(">f", bytes.fromhex(camera[name][2:]))[0]
                  for name in ("yaw", "pitch")]
    direction = [f32(unary("sinf", yaw)*unary("cosf", pitch)), unary("sinf", pitch),
                 f32(unary("cosf", yaw)*unary("cosf", pitch))]
    direction = [f32(x+0.) for x in direction]
    squares = [f32(x*x) for x in direction]
    length = unary("sqrtf", f32(f32(squares[0]+squares[1])+squares[2]))
    inverse = f32(1/length)
    return {"origin_m": camera["eye_m"], "direction": [bits(f32(x*inverse)) for x in direction]}


@unittest.skipUnless(shutil.which("bend"), "Bend compiler unavailable")
class ScheduleFloat(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory(prefix="bend-schedule-float-")
        cls.root = Path(cls.folder.name)
        for suffix in ("bend", "c", "js"):
            shutil.copyfile(ROOT/"src"/f"schedule_float.{suffix}", cls.root/f"schedule_float.{suffix}")
        cls.expected = []
        cls.expressions = []
        def add(kind, expression, value):
            cls.expressions.append(expression)
            cls.expected.append((kind, value))
        for value in (0., -0., .1, -.1, 2**-1074, 2**-1022, 1e-200, 1e200):
            add("double", f"F.evaluate({literal(value)})", value)
            if abs(value) < 3e38:
                add("json", f"F.bits({literal(value)})", bits(value))
        rng = random.Random(1729)
        for _ in range(40):
            a, b, c = [rng.uniform(-10000, 10000) for _ in range(3)]
            for name, value in (("Add", a+b), ("Sub", a-b), ("Mul", a*b), ("Div", a/b),
                                ("Atan2", math.atan2(a, b)), ("Hypot", math.hypot(a, b)), ("Max", max(a, b))):
                add("double", f"F.evaluate(F.{name}{{{literal(a)},{literal(b)}}})", value)
            add("double", f"F.evaluate(F.Sum3{{{literal(a)},{literal(b)},{literal(c)}}})", sum((a, b, c)))
            add("double", f"F.evaluate(F.Sqrt{{{literal(abs(a))}}})", math.sqrt(abs(a)))
            add("double", f"F.evaluate(F.Pow2{{{literal(a)}}})", a**2)
        value = 14.154949326059068
        add("double", f"F.evaluate(F.Pow2{{{literal(value)}}})", float.fromhex("0x1.90b9a573b3d54p+7"))
        for a, b in ((-0., 0.), (0., -0.)):
            add("double", f"F.evaluate(F.Max{{{literal(a)},{literal(b)}}})", max(a, b))
        for values in ((1e16, 1., -1e16), (-0., -0., -0.), (1., 2**-53, 2**-53),
                       (1e200, 1e-200, -1e200)):
            add("double", "F.evaluate(F.Sum3{" + ",".join(map(literal, values)) + "})", sum(values))
        for a, b in ((2**-1074, 2**-1074), (1e200, 1e-200), (1e-200, 1e-200),
                     (-0., 0.), (3., 4.)):
            add("double", f"F.evaluate(F.Hypot{{{literal(a)},{literal(b)}}})", math.hypot(a, b))
        for _ in range(24):
            eye = tuple(rng.uniform(-128, 128) for _ in range(3))
            look = tuple(rng.uniform(-128, 128) for _ in range(3))
            camera = reference_camera(eye, look)
            add("json", f"F.camera({vector(eye)},{vector(look)})", camera)
            add("json", f"F.ray_to({vector(eye)},{vector(look)})", reference_ray(eye, look))
            frozen_eye = [struct.unpack(">f", bytes.fromhex(word[2:]))[0] for word in camera["eye_m"]]
            yaw, pitch = [struct.unpack(">f", bytes.fromhex(camera[name][2:]))[0]
                          for name in ("yaw", "pitch")]
            add("json", f"F.center({vector(frozen_eye)},{literal(yaw)},{literal(pitch)})", reference_center(camera))
            add("json", f"F.exact.vector({vector(eye)})", [x.hex() for x in eye])
        add("json", "F.center(" + vector((0., 0., 0.)) + "," + literal(-0.) + "," + literal(0.) + ")",
            {"origin_m": ["0x00000000"]*3, "direction": ["0x00000000", "0x00000000", "0x3f800000"]})
        lines = ["import Base", "import ./schedule_float.bend as F", "def main() -> IO(Unit):", "  do IO<Unit>:"]
        for index, expression in enumerate(cls.expressions):
            lines += [f"    r{index} : String <- {expression}", f"    IO.print(r{index})"]
        source = cls.root/"probe.bend"
        source.write_text("\n".join(lines)+"\n")
        cls.binary = cls.root/"probe"
        subprocess.run(["bend", str(source), "-o", str(cls.binary)], check=True,
                       capture_output=True, text=True, timeout=120)

    @classmethod
    def tearDownClass(cls):
        cls.folder.cleanup()

    def test_native_effect_preserves_double_bytes_and_frozen_binary32_json(self):
        run = subprocess.run([str(self.binary), "--threads", "1"], check=True,
                             capture_output=True, text=True, timeout=30)
        rows = run.stdout.splitlines()
        self.assertEqual(len(rows), len(self.expected))
        for expression, row, (kind, expected) in zip(self.expressions, rows, self.expected):
            with self.subTest(expression=expression):
                if kind == "double":
                    self.assertEqual(struct.pack("<d", float.fromhex(row)), struct.pack("<d", expected))
                elif expression.startswith("F.exact.vector"):
                    self.assertEqual([float.fromhex(x).hex() for x in json.loads(row)], expected)
                else:
                    self.assertEqual(json.loads(row), expected)


if __name__ == "__main__":
    unittest.main()
