#!/usr/bin/env python3
"""Run controlled presentation failure probes beside actual X11 Vulkan execution."""
import argparse
import os
from pathlib import Path
import re
import subprocess
from check_window import isolated_display, instrument_window, deduplicate_native

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sanitize',action='store_true')
    parser.add_argument('--isolated-display',action='store_true')
    args=parser.parse_args()
    BUILD.mkdir(exist_ok=True)
    source=BUILD/'presentation-probes.c';binary=BUILD/'presentation-probes'
    subprocess.run(['bend','tests/presentation_probe_main.bend','-o',str(source)],cwd=ROOT,check=True)
    emitted=deduplicate_native(source.read_text())
    common=(ROOT/'../deps/bend-vulkan/tests/probes.c').read_text()
    allocator=common.split('static unsigned bv_test_barrier_calls;')[0]
    result_check=common[common.index('static void bv_test_result('):common.index('static Term bv_test_regions(')]
    probes=result_check+(ROOT/'tests/presentation_probes.c').read_text()
    macros=re.findall(r'^#define (CID_\w+) \d+$',emitted,re.M)
    def cid(match):
        name=match[1].replace('.','_')
        matches=[m for m in macros if m=='CID_'+name or m.endswith('_Vulkan_'+name)]
        if len(matches)!=1: raise ValueError(f'Missing or ambiguous constructor {name}: {matches}')
        return matches[0]
    probes=re.sub(r'CID\(([^)]+)\)',cid,probes)
    begin=emitted.index('// Bend native effect ABI.')
    end=emitted.index('static void __attribute__((constructor)) bv_register(void)',begin)
    native=emitted[begin:end]
    native=native.replace('malloc(','bv_test_alloc(').replace('calloc(','bv_test_calloc(').replace('realloc(','bv_test_realloc(')
    native=re.sub(r'\bfree\(','bv_test_free(',native)
    native=native.replace('static BvRow* bv_add(',allocator+'\nstatic BvRow* bv_add(',1)
    a=native.index('static Term bv_live_objects(');b=native.index('\n}',a)
    native=native[:a]+native[a:b].replace('return io_done(e,count);','if(!count)assert(bv_test_live_allocations==0);return io_done(e,count);')+native[b:]
    emitted=emitted[:begin]+native+probes+'\n'+emitted[end:]
    for name in ('create_swapchain','acquire','present','u64_roundtrip','create_graphics_pipeline'):
        emitted,n=re.subn(r'(io_eff\(CID_\w+, )bv_'+name+r'(\);)',r'\1test_'+name+r'\2',emitted)
        if n!=1: raise ValueError(f'{name} registration moved')
    source.write_text(instrument_window(emitted))
    flags=['-fsanitize=address,undefined','-fno-omit-frame-pointer'] if args.sanitize else []
    subprocess.run(['clang','-std=c11','-O1','-g',*flags,str(source),'-lpthread','-lm','-ldl','-o',str(binary)],cwd=ROOT,check=True)
    env=dict(os.environ,VK_INSTANCE_LAYERS='VK_LAYER_KHRONOS_validation',VK_LAYER_VALIDATE_SYNC='1',ASAN_OPTIONS='detect_leaks=0',UBSAN_OPTIONS='halt_on_error=1')
    with isolated_display(args.isolated_display):
        env['DISPLAY']=os.environ['DISPLAY']
        completed=subprocess.run([str(binary)],cwd=ROOT,env=env,text=True,capture_output=True,timeout=60)
    text=completed.stdout+completed.stderr
    (BUILD/'presentation-probes.log').write_text(text)
    print(text,end='',flush=True)
    completed.check_returncode()
    for marker in ('Controlled swapchain changing enumeration','Controlled acquire lifecycle','Independent acquisition completion','Same-index reacquisition binds and submits','Controlled present OOM retry','Native presentation borrowing','Bend target pipeline failure'):
        if marker not in text: raise AssertionError(f'Missing executed probe group {marker}')
    if 'Validation Error' in text or 'SYNC-HAZARD' in text: raise AssertionError(text)

if __name__=='__main__': main()
