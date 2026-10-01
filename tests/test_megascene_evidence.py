import math
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from megascene_evidence import decode, encode, run


DRIVER = """import Base
import ./evidence_value.bend as E
import ./megascene_scale.bend as S

def validation(value: Result<&2,&2,String,E.Signed>) -> E.Value:
  match value:
    case Fail{message}: E.Error{message}
    case Done{number}: E.int_value(number)

def handle(operation: String, +payload: E.Value) -> E.Value:
  match operation:
    case "echo": payload
    case "equality": E.boolean(E.eq(E.get(payload,"left"),E.get(payload,"right")))
    case "arithmetic":
      +a = E.int(E.get(payload,"left"))
      +b = E.int(E.get(payload,"right"))
      E.object([("sum",E.int_value(E.int_add(a,b))),
        ("difference",E.int_string(E.int_sub(a,b))),
        ("product",E.int_value(E.int_mul(a,b))),
        ("ratio",E.ratio(a,E.int_abs(b)))])
    case "rational":
      E.rational_value(E.rational_sub(E.rational(E.get(payload,"left")),E.rational(E.get(payload,"right"))))
    case "divide": E.Divide{E.get(payload,"left"),E.get(payload,"right")}
    case "objects": E.merge(E.get(payload,"left"),E.get(payload,"right"))
    case "canonical":
      validation(E.natural(payload))
    case "failure": E.Error{"preserved evidence failure"}
    case "missing": E.Error{"missing field:captured_review"}
    case "type_failure": E.Error{"type error:retained evidence must be an array"}
    case _: E.Null{}

def main() -> IO(Unit): E.main(~handle)
"""


class EvidenceTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        root = Path(cls.directory.name)
        for source in ("evidence_value.bend", "megascene_scale.bend"):
            shutil.copyfile(ROOT / "src" / source, root / source)
        (root / "driver.bend").write_text(DRIVER)
        cls.worker = root / "worker"
        subprocess.run(["bend", str(root / "driver.bend"), "-o", str(cls.worker)],
                       capture_output=True, text=True, check=True, timeout=120)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def invoke(self, operation, payload):
        with patch("megascene_bend.worker", return_value=self.worker):
            return run(operation, payload, "test_evidence")

    def test_native_roundtrip_retains_types_unicode_order_and_exact_numbers(self):
        payload = {"review": "🧩 Кириллица\n\t\0\ud800", "empty": "", "nested": [None, True, False, 0,
                   -7, 2 ** 200, -2 ** 140], "float": -0.0, "extension": {"z": 2, "a": 1}}
        result = self.invoke("echo", payload)
        self.assertEqual(result, payload)
        self.assertEqual(list(result["extension"]), ["z", "a"])
        self.assertEqual(struct.pack(">d", result["float"]), struct.pack(">d", -0.0))
        self.assertIs(type(result["nested"][1]), bool)
        self.assertIs(type(result["nested"][3]), int)

    def test_arbitrary_integer_and_native_signed_arithmetic(self):
        big = 10 ** 4700
        self.assertEqual(decode(encode(-big)), -big)
        result = self.invoke("arithmetic", {"left": -(2 ** 160), "right": 3})
        self.assertEqual(result["sum"], -(2 ** 160) + 3)
        self.assertEqual(result["difference"], "-1461501637330902918203684832716283019655932542979")
        self.assertEqual(result["product"], -3 * 2 ** 160)
        self.assertEqual(result["ratio"], -(2 ** 160) / 3)

    def test_native_numeric_equality_and_object_order(self):
        for left, right, expected in ((True, 1, True), (False, 0.0, True),
                                      (2 ** 53 + 1, float(2 ** 53 + 1), False),
                                      ({"a": [1, "x"], "b": None}, {"b": None, "a": [1.0, "x"]}, True),
                                      ({"a": None}, {"b": None}, False)):
            with self.subTest(left=left, right=right):
                self.assertIs(self.invoke("equality", {"left": left, "right": right}), expected)

    def test_native_ieee64_dyadic_arithmetic(self):
        for left, right in ((0.1, 0.2), (float.fromhex("0x1p-1074"), 0.0),
                            (-1024.5, 8.25), (float.fromhex("0x1.fffffffffffffp+1023"), 0.0)):
            with self.subTest(left=left, right=right):
                self.assertEqual(self.invoke("rational", {"left": left, "right": right}), left - right)

    def test_native_division_preserves_python_mixed_operand_rounding(self):
        for left, right in ((2 ** 53 + 1, 3.0), (2 ** 53 + 1, 3),
                            (3.0, 2 ** 53 + 1), (-2 ** 53 - 1, 3.0)):
            with self.subTest(left=left, right=right):
                self.assertEqual(self.invoke("divide", {"left": left, "right": right}), left / right)
        self.assertNotEqual((2 ** 53 + 1) / 3.0, (2 ** 53 + 1) / 3)

    def test_native_missing_field_preserves_key_error(self):
        with self.assertRaises(KeyError) as error:
            self.invoke("missing", {})
        self.assertEqual(error.exception.args, ("captured_review",))
        self.assertEqual(str(error.exception), "'captured_review'")

    def test_native_type_error_preserves_exception_class_and_message(self):
        with self.assertRaises(TypeError) as error:
            self.invoke("type_failure", {})
        self.assertEqual(str(error.exception), "retained evidence must be an array")

    def test_merge_and_failure_preserve_public_behavior(self):
        self.assertEqual(self.invoke("objects", {"left": {"a": 1, "b": 2}, "right": {"a": 7, "c": 9}}),
                         {"a": 7, "b": 2, "c": 9})
        with self.assertRaisesRegex(ValueError, "preserved evidence failure"):
            self.invoke("failure", {})
        for invalid in ("-1", "01", "+1", "-0", 1, True):
            with self.subTest(invalid=invalid):
                with self.assertRaisesRegex(ValueError, "noncanonical integer"):
                    self.invoke("canonical", invalid)
        self.assertEqual(self.invoke("canonical", "18446744073709551616"), 18446744073709551616)

    def test_special_floats_are_preserved_for_policy_validation(self):
        for value in (math.inf, -math.inf, math.nan):
            result = self.invoke("echo", value)
            self.assertTrue(math.isnan(result) if math.isnan(value) else result == value)

    def test_malformed_wire_data_is_rejected(self):
        for malformed in ("", "i1\ni2\n", "a1\n", "o1\n", "s0000\n"):
            with self.subTest(malformed=malformed):
                with self.assertRaises(ValueError):
                    decode(malformed)


if __name__ == "__main__":
    unittest.main()
