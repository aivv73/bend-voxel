"""Native driver fixtures plus synthetic report fixtures, never benchmark passes."""
import copy
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/"scripts"))
from megascene_gpu import read_stream, summarize
from megascene_inventory import SCHEMA, canonical

CONFIG = {"warmup": "1", "frames": "1"}
IDENTITY = {k: "fixture" for k in ("attempt_id", "series_id", "campaign_id")}


def fixtures(count=3):
    """A known ten-nanosecond GPU interval inside each 100 ns CPU frame."""
    records = []
    meta = dict(scope="submitted_frame_top_to_bottom", period_ns=1, period_bits="0x3f800000", valid_bits="64")
    def emit(kind, time, **fields):
        records.append(dict(schema=SCHEMA, record_type=kind, synthetic=True, **IDENTITY,
                            sequence=str(len(records)), clock_id="linux.CLOCK_MONOTONIC", time_ns=str(time), **fields))
    emit("gpu_capability",10**15,**meta,status="measured",reason="synthetic supported queue",queue_family="0",
         query_capacity="3721",begin_stage="TOP_OF_PIPE",end_stage="BOTTOM_OF_PIPE")
    for f in range(count):
        begin = 10**15+f*100+10
        emit("gpu_submission",begin,**meta,frame=str(f),submission=str(f),submit_begin_ns=str(begin))
        emit("gpu_interval",begin+110,**meta,frame=str(f),submission=str(f),submit_begin_ns=str(begin),
             completion_ns=str(begin+80),collection_frame=str(f+1) if f<count-1 else None,
             collection_phase="frame" if f<count-1 else "teardown",status="measured",reason="synthetic bounded pair",
             range_status="valid",unit="ns",vk_result="0",availability=["1","1"],raw_ticks=["100","110"],duration_ticks="10",value=10)
    # Serialize delayed collections in collection order, preserving origin IDs.
    records.sort(key=lambda r:int(r["time_ns"]))
    emit("gpu_complete",10**15+count*100+100,submissions=str(count))
    for i, r in enumerate(records):
        r["sequence"] = str(i)
    return records


class GpuReports(unittest.TestCase):
    def report(self, records):
        return summarize(records,[],[{"frame":str(f)} for f in range(3)],CONFIG)

    def test_origin_population_and_missing_tail(self):
        records = fixtures()
        value = self.report(records)
        self.assertTrue(value["required_evidence_complete"], value)
        self.assertEqual(value["populations"]["ordinary"]["count"],"1")
        last = next(r for r in records if r["record_type"] == "gpu_interval" and r["frame"] == "2")
        records.remove(last)
        result = self.report(records)
        self.assertEqual(result["counts"]["measured"],"2")
        self.assertEqual(result["intervals"][-1]["status"],"incomplete")
        self.assertIsNone(result["intervals"][-1]["value"])
        self.assertFalse(result["required_evidence_complete"])

    def test_forged_measurements_cannot_pass(self):
        mutations = [("value",0),("duration_ticks","9"),("raw_ticks",[str(2**64),"110"]),
                     ("valid_bits","8"),("period_ns",2),("completion_ns","0"),
                     ("completion_ns",str(2**64)),("availability",["0","1"]),
                     ("frame","2"),("submission","10"),("collection_frame","0"),("collection_frame","999"),
                     ("scope","fence_wait"),("range_status","single_wrap"),("vk_result","1")]
        for key,value in mutations:
            records = fixtures()
            r = next(r for r in records if r["record_type"] == "gpu_interval" and r["frame"] == "1")
            r[key] = value
            result = self.report(records)
            self.assertTrue(result["errors"],(key,value))
            self.assertFalse(result["required_evidence_complete"])

    def test_duplicate_and_lost_submission(self):
        records = fixtures()
        records[0]["query_capacity"] = "1"
        self.assertFalse(self.report(records)["required_evidence_complete"])
        for kind in ("gpu_capability","gpu_submission","gpu_interval","gpu_complete"):
            records = fixtures()
            index = next(i for i,r in enumerate(records) if r["record_type"] == kind)
            records.insert(index,copy.deepcopy(records[index]))
            self.assertFalse(self.report(records)["required_evidence_complete"],kind)
        records = [r for r in fixtures() if r.get("frame") != "2"]
        result = self.report(records)
        self.assertEqual(result["intervals"][-1]["status"],"incomplete")

    def test_parser_retains_damaged_prefix(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d)/"gpu.jsonl"
            records = fixtures()
            data = b"".join(canonical(r)+b"\n" for r in records)
            path.write_bytes(data)
            parsed,errors = read_stream(path,IDENTITY)
            self.assertEqual(parsed,records)
            self.assertFalse(errors)
            path.write_bytes(data+b'{"damaged":')
            parsed,errors = read_stream(path,IDENTITY)
            self.assertEqual(parsed,records)
            self.assertIn("truncated",errors[0])
            for key,value in (("sequence","9"),("schema","megascene-evidence/2"),("attempt_id","other"),
                              ("time_ns",str(2**64)),("time_ns","0")):
                mutated = copy.deepcopy(records)
                mutated[1][key] = value
                path.write_bytes(b"".join(canonical(r)+b"\n" for r in mutated))
                parsed,errors = read_stream(path,IDENTITY)
                self.assertEqual(len(parsed),1)
                self.assertTrue(errors)


class NativeGpu(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.binary = Path(cls.temp.name)/"gpu-fixtures"
        wrapped = ("vkCreateQueryPool", "vkDestroyQueryPool", "vkCmdResetQueryPool", "vkCmdWriteTimestamp", "vkGetQueryPoolResults")
        subprocess.run(["g++","-O2","-std=c++17",str(ROOT/"tests/native_gpu.cpp"),"-lvulkan","-lX11","-lcrypto",
                        *["-Wl,--wrap="+name for name in wrapped],"-o",str(cls.binary)],check=True,capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def fixture(self,mode):
        path = Path(self.temp.name)/(mode+".jsonl")
        subprocess.run([str(self.binary),str(path),mode],check=True,capture_output=True)
        records,errors = read_stream(path,IDENTITY)
        self.assertFalse(errors)
        result = summarize(records,[],[{"frame":"0"},{"frame":"1"}],CONFIG)
        self.assertFalse(result["errors"],result)
        return result,records

    def test_native_capacity_environment_is_bounded_and_legacy_is_preserved(self):
        environment={k:v for k,v in os.environ.items() if not k.startswith('MEGASCENE_')}
        result=subprocess.run([str(self.binary),'unused','capacity_env'],env=environment,capture_output=True,text=True)
        self.assertEqual((result.returncode,result.stdout),(0,'3721\n'))
        environment['MEGASCENE_FRAME_POLICY']='fixture'
        for capacity,code in (('21721',0),('21722',2),('3721',2),('0',2),('-1',2),('1e4',2),('',2),('999999999999999999999999',2)):
            result=subprocess.run([str(self.binary),'unused','capacity_env'],env={**environment,'MEGASCENE_QUERY_PAIRS':capacity},
                                  capture_output=True,text=True)
            self.assertEqual(result.returncode,code,capacity)
        result=subprocess.run([str(self.binary),'unused','capacity_env'],env=environment,capture_output=True)
        self.assertEqual(result.returncode,2)

    def test_driver_states_and_exact_values(self):
        for mode,status in (("supported","measured"),("zero","measured"),("wrapped","measured"),("fractional","measured"),
                            ("wide","measured"),("unsupported","unsupported"),("disabled","disabled"),
                            ("create_failure","collection_failure"),("collection_failure","collection_failure"),
                            ("high_bits","collection_failure"),("ambiguous","collection_failure"),("invalid_cpu","collection_failure")):
            result,records = self.fixture(mode)
            first = result["intervals"][0]
            self.assertEqual(first["status"],status,mode)
            self.assertEqual(first["value"],{"zero":0,"wrapped":10,"fractional":5,"wide":9}.get(mode,10) if status=="measured" else None,mode)
            self.assertEqual(result["required_evidence_complete"],status in {"measured","unsupported"})

    def test_delayed_pair_keeps_original_frame_and_bound(self):
        result,records = self.fixture("delayed")
        self.assertTrue(result["required_evidence_complete"])
        first = [r for r in records if r["record_type"] == "gpu_interval" and r["frame"] == "0"]
        self.assertEqual([r["status"] for r in first],["not_ready","measured"])
        self.assertEqual(first[0]["collection_frame"],"1")
        self.assertEqual(first[1]["collection_phase"],"teardown")
        self.assertEqual(first[0]["completion_ns"],first[1]["completion_ns"])

    def test_final_unavailable_and_sync_failure_are_not_zero(self):
        for mode,status in (("missing_tail","incomplete"),("sync_failure","collection_failure")):
            result,_ = self.fixture(mode)
            self.assertEqual(result["intervals"][-1]["status"],status)
            self.assertIsNone(result["intervals"][-1]["value"])
            self.assertFalse(result["required_evidence_complete"])


if __name__ == "__main__":
    unittest.main()
