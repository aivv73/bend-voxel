"""Runner-boundary resource/recorder fault injection; no real exhaustion."""
import ctypes
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from megascene_supervisor import Campaign, POLICY, Reference, resource_stop, audit_allocations
from megascene_inventory import read_json


class CheckpointStreamRetention(unittest.TestCase):
    def test_large_payload_remains_on_disk_with_frame_evidence(self):
        from megascene_supervisor import Tail
        from megascene_inventory import canonical
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/"cpu.jsonl"
            identity={"campaign_id":"fixture","series_id":"fixture","attempt_id":"fixture"}
            common={"schema":"megascene-evidence/1",**identity,"clock_id":"linux.CLOCK_MONOTONIC"}
            payload={**common,"record_type":"checkpoint","sequence":"0","time_ns":"1", "payload":{"cells":["1"]*10000}}
            frame={**common,"record_type":"frame","sequence":"1","time_ns":"2","frame":"0","begin_ns":"1","end_ns":"2"}
            raw=canonical(payload)+b"\n"+canonical(frame)+b"\n";path.write_bytes(raw)
            tail=Tail(path,identity,compact_cpu=True);tail.drain(final=True)
            self.assertIsNone(tail.error)
            self.assertEqual(tail.records[-1],frame)
            self.assertNotIn("payload",tail.records[0])
            self.assertEqual(path.read_bytes(),raw)


class SupervisorBoundary(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.retained = os.environ.get('MEGASCENE_FIXTURE_ARCHIVE')
        cls.area = tempfile.TemporaryDirectory()
        cls.root = Path(cls.area.name)
        source = cls.root/'commit.c'
        source.write_text('#define MEGA_REFERENCE_ONLY\n#include "'+str(ROOT/'src/vulkan/record.c')+'"\nint commit(void* p,const char* s,size_t n) { return mega_reference_commit(p,s,n); }\n')
        cls.helper = cls.root/'commit.so'
        subprocess.run(['gcc','-shared','-fPIC','-O2',str(source),'-o',str(cls.helper)],check=True)

    @classmethod
    def tearDownClass(cls):
        if cls.retained:
            shutil.copytree(cls.root,cls.retained)
        cls.area.cleanup()

    def invoke(self, case):
        path = self.root/case
        result = subprocess.run([sys.executable,str(ROOT/'tests/fixtures/supervisor_runner.py'),case,str(path),str(self.helper)],
                                capture_output=True,text=True,timeout=12)
        self.assertEqual(result.returncode,0,result.stderr)
        report = read_json((path/'supervision.json').read_text())
        return path, report

    def test_complete_and_action_references(self):
        for case, count in [('complete',2),('actions',5)]:
            path, report = self.invoke(case)
            self.assertEqual(report['termination']['cause'],'normal_exit',report)
            records = [read_json(l) for l in (path/'reference.jsonl').read_text().splitlines()]
            self.assertEqual(len(records),count)
            self.assertEqual([r['sequence'] for r in records],list(map(str,range(count))))
            self.assertEqual(report['completed_frame_prefix'],'2')
            self.assertFalse(report['errors'])

    def test_stops_and_crash_keep_committed_prefix(self):
        expected = {'rss':'process_rss_reserve','ram':'available_ram_reserve','vram':'device_free_reserve','heap':'heap_budget_reserve',
                    'malformed_monitor':'monitoring_failure','monitor_error':'monitoring_failure','stale':'monitoring_failure','monitor_exit':'monitoring_failure',
                    'monitor_hang':'monitoring_failure','missing_heap':'monitoring_failure',
                    'startup':'startup_deadline','watchdog':'completion_watchdog','case':'case_deadline','campaign':'campaign_deadline',
                    'allocation':'allocation_error','device_loss':'device_loss','crash':'unexplained_crash','external':'external_interruption',
                    'lost_reference':'persistence_failure','overflow':'persistence_failure','tail':'persistence_failure',
                    'persistence':'persistence_failure','reference_gap':'persistence_failure','preflight_reserve':'process_rss_reserve'}
        for case, cause in expected.items():
            with self.subTest(case=case):
                path, report = self.invoke(case)
                self.assertEqual(report['termination']['cause'],cause,report)
                if case in ('crash','allocation','device_loss','tail','case','watchdog','external'):
                    self.assertEqual(report['completed_frame_prefix'],'2',report)
                if case == 'tail': self.assertTrue((path/'cpu.jsonl').read_bytes().endswith(b'{"damaged":'))
                if case == 'preflight_reserve': self.assertIsNone(report['termination']['exit_code'])

    def test_native_allocation_identity_failure_and_totals(self):
        binary = self.root/'native-supervision'
        subprocess.run(['g++','-O2','-std=c++17',str(ROOT/'tests/native_supervision.cpp'),'-lvulkan','-lX11','-lcrypto',
                        '-Wl,--wrap=vkAllocateMemory','-Wl,--wrap=vkFreeMemory','-Wl,--wrap=vkGetPhysicalDeviceMemoryProperties',
                        '-o',str(binary)],check=True)
        path = self.root/'native-allocations.jsonl'
        subprocess.run([str(binary),str(path)],check=True)
        records = [read_json(l) for l in path.read_text().splitlines()]
        self.assertEqual([r['record_type'] for r in records],
                         ['ledger_start','allocate','allocate','free','allocation_failed','free','vulkan_error'])
        self.assertEqual([r['live_bytes'] for r in records[:-1]],['0','4096','12288','8192','8192','0'])
        self.assertEqual([r['allocation_id'] for r in records[1:-1]],['1','2','1','3','2'])
        self.assertEqual(records[4]['vk_result'],'-2')
        self.assertEqual(records[4]['size_bytes'],'16384')
        self.assertEqual(records[1]['heap'],'1')
        self.assertEqual(records[2]['heap'],'0')
        self.assertEqual(audit_allocations(records,normal=True)['peak_bytes'],'12288')
        records[3]['size_bytes']='1'
        with self.assertRaisesRegex(ValueError,'free identity'): audit_allocations(records)

    def test_exact_reserve_boundaries(self):
        now = time.monotonic_ns()
        sample = dict(record_type='host_sample',status='measured',device='gpu',sample_begin_ns=str(now),sample_end_ns=str(now),
                      rss_bytes=str(POLICY['rss_bytes']-1),available_ram_bytes=str(POLICY['available_ram_bytes']),device_free_bytes=str(POLICY['device_free_bytes']))
        self.assertIsNone(resource_stop(sample,now,'gpu'))
        self.assertEqual(resource_stop(sample|{'rss_bytes':str(POLICY['rss_bytes'])},now)[0],'process_rss_reserve')
        self.assertIsNone(resource_stop(sample,now+10**9))
        self.assertEqual(resource_stop(sample,now+10**9+1)[0],'monitoring_failure')
        heap = dict(record_type='heap_sample',status='measured',device='gpu',sample_begin_ns=str(now),sample_end_ns=str(now),
                    heaps=[dict(heap='0',usage_bytes='89',budget_bytes='100')])
        self.assertIsNone(resource_stop(heap,now))
        heap['heaps'][0]['usage_bytes']='90'
        self.assertEqual(resource_stop(heap,now)[0],'heap_budget_reserve')

    def test_campaign_is_not_reset_and_requires_explicit_resume(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d)
            campaign = Campaign(path)
            campaign_id = campaign.value['campaign_id']
            campaign.attempt('first',path/'summary.json','external_interruption')
            campaign.close(False)
            with self.assertRaisesRegex(ValueError,'additional-allowance'): Campaign(path)
            resumed = Campaign(path,1)
            self.assertEqual(resumed.value['campaign_id'],campaign_id)
            self.assertEqual(resumed.value['additional_allowances'][0]['seconds'],'1')
            self.assertGreater(int(resumed.value['elapsed_ns']),0)
            resumed.attempt('second',path/'summary.json','normal_exit')
            resumed.close(True)
            continued = Campaign(path)
            self.assertEqual(len(continued.value['attempts']),2)
            continued.value['allowance_ns']='0'
            continued.close(False)
            with self.assertRaisesRegex(ValueError,'additional-allowance'): Campaign(path)


if __name__ == '__main__': unittest.main()
