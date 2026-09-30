import copy
import hashlib
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from megascene import configuration, parser, snapshot
from megascene_inventory import canonical, SCHEMA
from megascene_static import schedule
from megascene_performance import policy_bytes, validate, FRAME_COUNT, memory_observations, report_series
from megascene_gpu import summarize
from megascene_calibration_series import matrix, scope, _values, plan
from megascene_report import distribution, calibration_result
from test_megascene_gpu import fixtures
from test_megascene_report import fixture, classify_fixture

BASE=dict(preset='small',side_m='64',seed='45',threads='6',fragment_budget='2048',resolution='1920x1080',
          profile='full',warmup='120',frames='21600',diagnostic=None,control=None)


class PerformanceProtocol(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.frozen={case:schedule({**BASE,'case':case,'schedule':case+'-perf-v2'}) for case in ('static','history')}

    def test_public_fixed_scope_and_legacy_defaults(self):
        args=['--case','history','--threads','6','--archive','/home/aivv/perf-test','--output','build/perf-test']
        self.assertEqual(configuration(parser().parse_args(args))['frames'],'3600')
        admitted=configuration(parser().parse_args(args+['--schedule','history-perf-v2']))
        self.assertEqual((admitted['warmup'],admitted['frames']),('120','21600'))
        for change in (['--frames','21601'],['--frames','3600'],['--warmup','0'],['--threads','12'],
                       ['--preset','large'],['--seed','46'],['--resolution','640x360'],['--fragment-budget','100']):
            with self.assertRaises(ValueError,msg=change):
                configuration(parser().parse_args(args+['--schedule','history-perf-v2']+change))
        self.assertEqual((plan()['configuration_count'],plan()['control_count']),(12,72))
        self.assertEqual((plan('performance-v2')['configuration_count'],plan('performance-v2')['control_count']),(2,12))

    def test_correction_series_cannot_escape_configuration_namespace(self):
        from megascene_calibration_series import run_series
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);archive=root/'archive';work=root/'work'
            for path in (root/'series.json',archive/'calibration-series-v2/history-small-6/revision-2/series.json',
                         archive/'calibration-series-v2/static-small-6/revision-2/other.json',
                         archive/'calibration-series-v2/static-small-6/revision-2/../../outside/series.json'):
                with self.assertRaisesRegex(ValueError,'configuration namespace'):
                    run_series(archive,work,'static','small',6,protocol='performance-v2',series_path=path)
            self.assertFalse(archive.exists())

    def test_history_validation_has_its_own_bounded_deadline(self):
        from megascene_supervisor import worker_case_policy, NS
        args=['--case','static','--threads','6','--archive','/home/aivv/perf-test',
              '--output','build/perf-test','--schedule','static-perf-v2']
        self.assertNotIn('validation_deadline_s',configuration(parser().parse_args(args)))
        args[1]='history'
        args[-1]='history-perf-v2'
        self.assertEqual(configuration(parser().parse_args(args))['validation_deadline_s'],'480')
        self.assertEqual(configuration(parser().parse_args(args+['--deadline','30']))['validation_deadline_s'],'30')
        config={**BASE,'case':'history','schedule':'history-perf-v2','deadline_s':'300','validation_deadline_s':'480'}
        policy,duration=worker_case_policy(config,{'MEGASCENE_VALIDATE':'1'})
        self.assertEqual((policy['case_ns'],duration),(480*NS,480*NS))
        for env in ({},{'MEGASCENE_VALIDATE':'0'}):
            policy,duration=worker_case_policy(config,env)
            self.assertEqual((policy['case_ns'],duration),(300*NS,300*NS))
        config['validation_deadline_s']='30'
        self.assertEqual(worker_case_policy(config,{'MEGASCENE_VALIDATE':'1'})[1],30*NS)
        config['schedule']='history-v1'
        self.assertEqual(worker_case_policy(config,{'MEGASCENE_VALIDATE':'1'})[1],300*NS)

    def test_excluded_control_blocks_resume_even_if_run_list_is_clean(self):
        from megascene_calibration_series import run_series, ORDER
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);archive=root/'archive';work=root/'work'
            path=archive/'calibration-series-v2/history-small-6/revision-2/series.json'
            path.parent.mkdir(parents=True)
            snapshot(path,{'scope':scope(matrix('performance-v2')[1]),'order':list(ORDER),
                           'runs':[],'controls':[{'returncode':0,'measurement_exclusion':'background load'}]})
            with self.assertRaisesRegex(ValueError,'failed run'):
                run_series(archive,work,'history','small',6,additional=1,
                           protocol='performance-v2',series_path=path)
            self.assertFalse(work.exists())

    def test_history_workload_and_policy_are_literal(self):
        frozen=self.frozen['history']
        self.assertEqual(len(frozen['frames']),21721)
        self.assertEqual(len(policy_bytes(frozen)),173768)
        self.assertEqual({phase:sum(f['phase']==phase for f in frozen['frames']) for phase in ('ordinary','motion','edit')},
                         {'ordinary':20328,'motion':1152,'edit':120})
        self.assertEqual([int(a['frame']) for a in frozen['actions'][:10]],
                         [121,301,481,661,841,853,1201,1381,1561,1741])
        self.assertEqual(frozen['actions'][-1]['frame'],'21541')
        self.assertEqual(frozen['required_checkpoints'][-2:],
                         [{'name':'history_overview','frame':'21661'},{'name':'completion','frame':'21720'}])
        self.assertEqual(sum(int(a['expected_removed_cells']) for a in frozen['actions']),2440)
        self.assertEqual(sum(f['phase']=='ordinary' for f in self.frozen['static']['frames']),21600)
        self.assertIsNone(self.frozen['static']['performance_protocol']['history_action_offsets'])

    def test_saved_historical_bytes_remain_exact(self):
        expected={'static':'2e56c62b00a861036eee988210b9910c52ecbaf24077d80223b8d6dbe6dccec8',
                  'history':'b1808644656889ff5923e2c0166d109d484b18410151ff23b305bee927796217'}
        for case in expected:
            old=schedule({**BASE,'case':case,'schedule':case+'-v1','frames':'3600'})
            self.assertEqual(hashlib.sha256(canonical(old)).hexdigest(),expected[case])

    def test_public_review_accepts_both_admitted_v2_validation_routes(self):
        from megascene_traversal import review_evidence
        from megascene_review import assess
        from megascene_inventory import read_json
        for case,mode in ((case,mode) for case in ('static','history') for mode in ('on','off')):
            with tempfile.TemporaryDirectory() as folder:
                root=Path(folder)
                captures=root/'validation/captures'
                captures.mkdir(parents=True)
                frozen=self.frozen[case]
                snapshot(root/'schedule.json',frozen)
                records=[]
                for view in frozen['review_views']:
                    frame=view['frame']
                    (captures/f'frame-{int(frame):04d}.ppm').write_bytes(b'P6\n2 1\n255\n\x11\x22\x33\x44\x55\x66')
                    records.extend([{'record_type':'capture','rendered_frame':frame},
                        {'record_type':'render_work','frame':frame,'shadow_extent_m':['0x42800000']*2,
                         'shadow_texel_m':['0x3dcccccd']*2,'shadow_fit_min_margin_texels':'0x3f800000'}])
                review=review_evidence(root,frozen,records)
                self.assertEqual(review['status'],'awaiting_named_feature_review')
                snapshot(root/'review.json',review)
                snapshot(root/'summary.json',{'attempt_kind':'validation_only','schedule_completion':{'status':'pass'},'state_correctness':{'status':'pass'},
                    'rendering_correctness':{'status':'pass'},'visual_quality':{'status':'inconclusive'}})
                from megascene import artifact
                manifest={'schema':SCHEMA,'synthetic':False,'attempt_kind':'calibration_'+mode,
                    'effective':{**BASE,'case':case,'schedule':case+'-perf-v2','calibration_mode':mode,'validation_only':True},
                    'evidence':[artifact(root/name,root) for name in ('schedule.json','summary.json','review.json')]}
                snapshot(root/'manifest.json',manifest)
                answers=root/'answers.json'
                snapshot(answers,{'schema':'megascene-feature-assessments/1','views':{
                    view['name']:{feature['name']:{'geometry':'correct','readability':'readable'}
                                  for feature in view['features']} for view in review['views']}})
                if mode=='off':
                    manifest['effective']['validation_only']=False
                    snapshot(root/'manifest.json',manifest)
                    with self.assertRaisesRegex(ValueError,'complete bundle required'):
                        assess(root,answers,'fixture reviewer')
                    self.assertFalse((root/'assessments.json').exists())
                    manifest['effective']['validation_only']=True
                    snapshot(root/'manifest.json',manifest)
                self.assertEqual(assess(root,answers,'fixture reviewer'),'pass')
                self.assertEqual(read_json((root/'review.json').read_text())['schedule_sha256'],
                                 hashlib.sha256((root/'schedule.json').read_bytes()).hexdigest())

    def test_disguised_empty_tail_and_bad_policy_fail_admission(self):
        for mutation in ('duration','density','offsets','flags','phase'):
            frozen=copy.deepcopy(self.frozen['history'])
            if mutation=='duration': frozen['measured_frames']='36000'
            elif mutation=='density': frozen['actions'][-1]['frame']='1549'
            elif mutation=='offsets': frozen['performance_protocol']['history_action_offsets'][-1]='1428'
            elif mutation=='flags': frozen['frames'][21661]['policy_flags']='0'
            else: frozen['frames'][841]['phase']='ordinary'
            with self.assertRaises(ValueError,msg=mutation): validate(frozen)

    def test_gpu_capacity_and_disjoint_origin_populations(self):
        records=fixtures(855)
        records[0]['query_capacity']='21721'
        config={**BASE,'case':'history','schedule':'history-perf-v2'}
        cpu=[{'frame':str(i)} for i in range(855)]
        result=summarize(records,[],cpu,config,self.frozen['history'])
        self.assertFalse(result['errors'],result['errors'])
        self.assertEqual({k:result['populations'][k]['count'] for k in ('ordinary','motion','edit')},
                         {'ordinary':'716','motion':'12','edit':'6'})
        for capacity in ('3721','21720','21722'):
            records[0]['query_capacity']=capacity
            self.assertTrue(summarize(records,[],cpu,config,self.frozen['history'])['errors'])
        bad=copy.deepcopy(self.frozen['history']);del bad['frames'][121]['phase']
        self.assertTrue(summarize(records,[],cpu,config,bad)['errors'])

    def test_edit_seconds_cannot_qualify_ordinary_calibration(self):
        frozen=self.frozen['history']
        config={**BASE,'case':'history','schedule':'history-perf-v2'}
        records=[];at=10**15
        for f in frozen['frames']:
            duration=100 if f['phase']=='ordinary' else 1_000_000_000
            end=at+duration
            records.append(dict(record_type='frame',frame=f['frame'],population=f['phase'],begin_ns=str(at),
                                end_ns=str(end),duration_ns=str(duration)))
            if f['actions']:
                a=frozen['actions'][int(f['actions'][0])]
                outcome=dict(accepted=True,removed_cells=a['expected_removed_cells'],target_m=a['target_m'])
                records.extend([dict(record_type='edit_begin',frame=f['frame'],action=a['action'],begin_ns=str(at+10)),
                    dict(record_type='action',frame=f['frame'],action=a['action'],accepted=True,
                         removed_cells=a['expected_removed_cells'],outcome=outcome),
                    dict(record_type='edit',frame=f['frame'],action=a['action'],accepted=True,
                         removed_cells=a['expected_removed_cells'],begin_ns=str(at+10),end_ns=str(end),duration_ns=str(duration-10))])
            at=end
        manifest=dict(effective=config,attempt_kind='calibration_on',attempt_id='fixture',synthetic=False)
        summary=dict(attempt_id='fixture',schedule_completion={'status':'pass'},state_correctness={'status':'pass'},
                     termination={'cause':'normal_exit'},evidence_errors=[],
                     populations={'ordinary':distribution([100]*20328)},accepted_edits=distribution([999999990]*120))
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for name,value in (('manifest.json',manifest),('summary.json',summary),('schedule.json',frozen),
                               ('validation.json',{'status':'pass','checked_frames':'21721'})):
                snapshot(root/name,value)
            with patch('megascene_calibration_series.read_stream',return_value=(records,[])):
                result=_values(root,scope(config),'on')
        self.assertGreater(result['measured_duration_ns'],10_000_000_000)
        self.assertEqual(result['ordinary_duration_ns'],2032800)
        self.assertFalse(result['sufficient'])

    def test_calibration_counts_are_part_of_v2_applicability(self):
        config={**BASE,'case':'history','schedule':'history-perf-v2'}
        calibration={'schema':SCHEMA,'record_type':'calibration','status':'pass','reference':'fixture', 'scope':scope(config)}
        self.assertEqual(calibration_result(calibration,config,'calibration_on')['status'],'pass')
        calibration['scope']['frames']='3600'
        with self.assertRaises(ValueError):calibration_result(calibration,config,'calibration_on')

    def test_reader_rejects_forged_motion_population(self):
        data=fixture()
        data['manifest']['effective'].update(warmup='120',frames='21600',schedule='static-perf-v2')
        data['schedule']=self.frozen['static']
        data['calibration']=None
        for row in data['cpu']:
            if row['record_type']=='frame' and 1<=int(row['frame'])<=120: row['population']='warmup'
        next(r for r in data['cpu'] if r['record_type']=='frame' and r['frame']=='121')['population']='motion'
        result=classify_fixture(data)
        self.assertIn('CPU frame population mismatch',result['evidence_errors'])
        self.assertNotEqual(result['schedule_completion']['status'],'pass')

    def test_sampled_memory_and_reserved_reference_bytes_are_exposed(self):
        identity={k:'fixture' for k in ('attempt_id','campaign_id','series_id')}
        def row(index,**fields):
            return dict(schema=SCHEMA,**identity,sequence=str(index),clock_id='linux.CLOCK_MONOTONIC',time_ns=str(index+1),**fields)
        resources=[row(0,record_type='host_sample',rss_bytes='12',available_ram_bytes='100',device_free_bytes='80'),
                   row(1,record_type='host_sample',rss_bytes='24',available_ram_bytes='90',device_free_bytes='70'),
                   row(2,record_type='heap_sample',heaps=[dict(heap='0',usage_bytes='20',budget_bytes='100')])]
        ledger={'live_bytes':'0','peak_bytes':'0','live_allocations':'0','scope':'explicit Vulkan allocations; not residency or heap budgets'}
        summary={'termination':{'cause':'normal_exit'},'supervision':dict(observed_maxima={'rss_bytes':'24'},
            observed_minima={'available_ram_bytes':'90','device_free_bytes':'70'},allocation_ledger=ledger,reference_capacity='22081')}
        manifest={**identity,'worker_environment':{'MEGASCENE_QUERY_PAIRS':'21721'}}
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            (root/'resources.jsonl').write_bytes(b''.join(canonical(r)+b'\n' for r in resources))
            (root/'allocations.jsonl').write_bytes(canonical(row(0,record_type='ledger_start',live_bytes='0',peak_bytes='0'))+b'\n')
            with (root/'reference.shared').open('wb') as stream: stream.truncate(22610976)
            (root/'frame-policy.bin').write_bytes(policy_bytes(self.frozen['history']))
            result=memory_observations(root,manifest,summary)
            self.assertEqual((result['rss_peak_bytes'],result['device_free_min_bytes'],result['reference_reserved_bytes']),
                             ('24','70','22610976'))
            self.assertEqual(result['heaps']['0']['headroom_min_bytes'],'80')
            self.assertIsNone(result['query_pool_device_bytes'])
            summary['supervision']['observed_maxima']['rss_bytes']='25'
            with self.assertRaises(ValueError):memory_observations(root,manifest,summary)

    def test_reference_recorder_admits_whole_history_and_rejects_unbounded_capacity(self):
        from megascene_supervisor import Reference
        identity={k:'fixture' for k in ('attempt_id','campaign_id','series_id')}
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            reference=Reference(root,identity,22081)
            try:self.assertEqual(reference.path.stat().st_size,22610976)
            finally:reference.close()
            with self.assertRaises(ValueError):Reference(root,identity,32769)

    def test_comparison_preserves_failed_and_noisy_calibration(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'series.json'
            snapshot(path,{'protocol':'performance-v2','scope':scope(matrix('performance-v2')[0]),
                           'controls':[],'validations':{}})
            for state in ('failed','noisy'):
                assessment={'status':state,'scope':scope(matrix('performance-v2')[0]),'reason':'observed control ratio',
                            'control_count':0,'statistics':{'ordinary_mean':{'status':state}}}
                with patch('megascene_calibration_series.assess',return_value=assessment):
                    result=report_series(path,'static')
                self.assertEqual(result['calibration']['status'],state)
                self.assertEqual(result['calibration']['statistics']['ordinary_mean']['status'],state)
                self.assertEqual(result['canonical_repeat_agreement']['status'],'inconclusive')
                self.assertIn('actual status',result['qualification'])

    def test_partial_series_reports_unavailable_and_unusable_controls_without_metrics(self):
        from megascene_calibration_series import ORDER
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            damaged=root/'damaged'
            damaged.mkdir()
            path=root/'series.json'
            controls=[{'mode':'off','archive':None,'output':str(root/'failed-launch'),'returncode':2},
                      {'mode':'on','archive':str(damaged),'output':str(root/'partial'),'returncode':0},
                      {'mode':'on','archive':str(damaged),'output':str(root/'contaminated'),'returncode':0,
                       'measurement_exclusion':'background verification overlapped timing'}]
            snapshot(path,{'schema':SCHEMA,'protocol':'performance-v2','scope':scope(matrix('performance-v2')[0]),
                           'order':list(ORDER),'controls':controls,'validations':{}})
            result=report_series(path,'static')
            self.assertEqual(result['calibration']['status'],'insufficient')
            self.assertEqual(result['canonical_repeat_agreement']['status'],'inconclusive')
            self.assertEqual([row['evidence_status'] for row in result['controls']],['unavailable','unusable','unusable'])
            for control,row in zip(controls,result['controls']):
                for key in control:self.assertEqual(row[key],control[key])
                self.assertTrue(row['evidence_errors'])
                self.assertIsNone(row['frame_intervals'])
                self.assertIsNone(row['memory'])


class NativePolicyBoundary(unittest.TestCase):
    @unittest.skipUnless(shutil.which('g++'),'C++ compiler unavailable')
    def test_real_parser_rejects_corrupt_input(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);worker=root/'policy'
            subprocess.run(['g++','-std=c++17',str(ROOT/'tests/native_performance.cpp'),'-o',str(worker)],check=True,capture_output=True)
            frozen=schedule({**BASE,'case':'static','schedule':'static-perf-v2'})
            data=policy_bytes(frozen)
            path=root/'policy.bin'
            for value,expected in ((data,0),(data[:-1],2),(data+b'\0',2),
                    (struct.pack('<I',5)+data[4:],2),(data[:4]+struct.pack('<I',8)+data[8:],2)):
                path.write_bytes(value)
                self.assertEqual(subprocess.run([str(worker),str(path),'static']).returncode,expected)


if __name__=='__main__':unittest.main()
