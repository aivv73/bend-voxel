#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build/milestone-6-production'
COMPILE_TIMEOUT=1800
FORBIDDEN=('Validation Error','SYNC-HAZARD','ERROR: AddressSanitizer','runtime error:','SOME PROOFS FAIL')


def producer_sources():
    paths=[ROOT/'../deps/bend-vulkan/Vulkan.bend',ROOT/'tests/appearance_render.bend',ROOT/'tools/build_shaders.py']
    paths += list(ROOT.parent.glob('*.bend'))
    paths += [p for folder in ('examples', 'shaders', 'src', '../deps/bend-vulkan/src',
                              '../deps/bend-vulkan/examples', '../deps/bend-vulkan/shaders',
                              '../deps/bend-vulkan/deps/bend-collections/src')
              for p in sorted((ROOT/folder).rglob('*'))
              if p.is_file() and p.suffix in ('.bend','.vert','.frag','.glsl','.c','.h')]
    return {os.path.relpath(p,ROOT):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def shadow_gate():
    output=BUILD/'shadow-causality'
    snapshot=output/'snapshot'
    snapshot.mkdir(parents=True,exist_ok=True)
    device=subprocess.run(['vulkaninfo'],cwd=ROOT,text=True,capture_output=True,check=True,timeout=60)
    device_path=output/'device.txt'
    device_path.write_text(device.stdout)
    (BUILD/'device-precision.log').write_text(device.stdout)
    (output/'device.stderr').write_text(device.stderr)
    sources=[BUILD/(state+suffix) for state in ('intact','carved')
             for suffix in ('.body.json','.uniform','.shadow')]
    sources += [ROOT/'build/milestone-6-reference/receivers.jsonl',device_path]
    before={p:p.stat() for p in sources}
    inputs=[]
    for path in sources:
        data=path.read_bytes()
        (snapshot/path.name).write_bytes(data)
        inputs.append(dict(name=path.name,source=str(path),size=len(data),
                           mtime_ns=before[path].st_mtime_ns,sha256=hashlib.sha256(data).hexdigest()))
    for path in sources:
        after=path.stat()
        assert (before[path].st_ino,before[path].st_size,before[path].st_mtime_ns)==(after.st_ino,after.st_size,after.st_mtime_ns), 'Capture changed during shadow snapshot'
        assert hashlib.sha256(path.read_bytes()).hexdigest()==next(r['sha256'] for r in inputs if r['source']==str(path))
    (snapshot/'manifest.json').write_text(json.dumps(dict(inputs=inputs),indent=2)+'\n')
    provenance=ROOT/'build/milestone-6-reference/dependency-sha256.json'
    (snapshot/'reference-dependency-sha256.json').write_bytes(provenance.read_bytes())
    commands=[]
    controls={}
    gate_sources={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
                  for name in ('tools/check_production.py','tools/shadow_causality.py')}
    for control in (None,'clear_missing_pass','zero_depth','shifted_one_texel','stable_depth_spike','edge_depth_spike'):
        name=control or 'actual'
        target=output/'negative-controls'/name if control else output
        command=[sys.executable,'tools/shadow_causality.py','--snapshot',str(snapshot),
                 '--device',str(snapshot/'device.txt'),'--output',str(target)]
        if control:command+=['--negative-control',control]
        result=subprocess.run(command,cwd=ROOT,text=True,capture_output=True,timeout=600)
        (output/(name+'.log')).write_text(result.stdout+result.stderr)
        commands.append(dict(command=command,status=result.returncode,expected_status=1 if control else 0,
                             log=name+'.log',gate_sources=gate_sources))
        (output/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
        assert result.returncode==(1 if control else 0), (name,result.stdout+result.stderr)
        report=json.loads((target/'results.json').read_text())
        assert report['pass_gate']==(control is None), name
        if control:
            assert all(r['unexplained_depth_count']>0 for r in report['states'].values()), name
            controls[control]=dict(status=result.returncode,pass_gate=report['pass_gate'],
                                   unexplained_depth_counts={s:r['unexplained_depth_count'] for s,r in report['states'].items()})
    report=json.loads((output/'results.json').read_text())
    report['negative_controls']=controls
    report['negative_controls_pass']=len(controls)==5
    report['gate_sources']=gate_sources
    (output/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    for row in inputs:
        assert hashlib.sha256((snapshot/row['name']).read_bytes()).hexdigest()==row['sha256']
    print('Original-Body actual512 D32 caster/visibility causality and five corrupt-depth negative controls passed')
    print('Shadow evidence: '+str(output/'results.json'))


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--sanitize',action='store_true')
    parser.add_argument('--shadow-only',action='store_true',help='check coherent existing captures without rendering again')
    args=parser.parse_args()
    BUILD.mkdir(parents=True,exist_ok=True)
    if args.shadow_only:
        shadow_gate()
        return
    sources=producer_sources()
    (BUILD/'producer-source-sha256.json').write_text(json.dumps(dict(timing='before Bend emission',sources=sources),indent=2)+'\n')
    commands=[]

    def run(command,name,env=None,timeout=600):
        command=list(map(str,command))
        result=subprocess.run(command,cwd=ROOT,env=env,text=True,capture_output=True,timeout=timeout)
        (BUILD/(name+'.log')).write_text(result.stdout+result.stderr)
        commands.append(dict(command=command,status=result.returncode,log=name))
        (BUILD/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
        assert result.returncode==0 and not any(value in result.stdout+result.stderr for value in FORBIDDEN),name
        return result.stdout

    source=BUILD/'production.c'; binary=BUILD/'production'
    run(['bend','tests/appearance_render.bend','-o',source],'bend-c',timeout=COMPILE_TIMEOUT)
    run(['clang','-std=c11','-O1',source,'-lpthread','-lm','-ldl','-o',binary],'compile',timeout=COMPILE_TIMEOUT)
    preprocessed=BUILD/'production-preprocessed.c'
    run(['clang','-std=c11','-E','-P',source,'-o',preprocessed],'preprocess')
    assert not re.search(r'\b(?:cuLaunchKernel|cuInit|nvrtcCreateProgram)\s*\(',preprocessed.read_text()), 'Headless production retains CUDA dispatch'
    linked=run(['ldd',binary],'linked')
    assert not any(value in linked for value in ('libX11','libxcb')), 'Headless production gained a display dependency'
    device=run(['vulkaninfo','--summary'],'device')
    run(['vulkaninfo'],'device-precision')
    validation='VK_LAYER_KHRONOS_validation' in device
    normal_output=run([binary,'+RTS','--threads','4','-RTS'],'normal')
    assert 'Production shared recorder live=0' in normal_output
    run([sys.executable,'tools/production_oracle.py'],'normal-oracle')
    (BUILD/'normal-results.json').write_bytes((BUILD/'results.json').read_bytes())

    def artifact_hashes():
        return {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(BUILD.iterdir())
                if p.suffix in ('.rgba','.depth','.shadow','.uniform') or p.name.endswith('.body.json')}

    expected=artifact_hashes()
    statuses=dict(normal='pass',validation='unavailable',sanitized='not requested')
    validation_env=dict(os.environ,VK_INSTANCE_LAYERS='VK_LAYER_KHRONOS_validation',VK_LAYER_VALIDATE_SYNC='1') if validation else dict(os.environ)
    if validation:
        output=run([binary,'+RTS','--threads','4','-RTS'],'validation',validation_env)
        assert 'Production shared recorder live=0' in output
        assert expected==artifact_hashes(), 'Repeated validation run changed exact production artifacts'
        run([sys.executable,'tools/production_oracle.py'],'validation-oracle')
        (BUILD/'validation-results.json').write_bytes((BUILD/'results.json').read_bytes())
        statuses['validation']='pass'
    if args.sanitize:
        sanitized=BUILD/'production-sanitized'
        run(['clang','-std=c11','-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',source,
             '-lpthread','-lm','-ldl','-o',sanitized],'sanitizer-compile',timeout=COMPILE_TIMEOUT)
        output=run([sanitized,'+RTS','--threads','4','-RTS'],'sanitized',dict(validation_env,ASAN_OPTIONS='detect_leaks=0:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1'))
        assert 'Production shared recorder live=0' in output
        assert expected==artifact_hashes(), 'Sanitizers changed exact production artifacts'
        run([sys.executable,'tools/production_oracle.py'],'sanitized-oracle')
        (BUILD/'sanitized-results.json').write_bytes((BUILD/'results.json').read_bytes())
        statuses['sanitized']='pass'
    run([sys.executable,'tools/reference_lighting.py','--gpu-metadata',BUILD/'gpu-receivers.json',
         '--gpu-depth',BUILD/'intact.shadow'],'actual-gpu-depth-oracle')
    shadow_gate()
    assert sources==producer_sources(), 'Renderer source changed during production acceptance'
    producer=dict(sources=sources,emitted_c_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  normal_binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest())
    if args.sanitize:producer['sanitized_binary_sha256']=hashlib.sha256(sanitized.read_bytes()).hexdigest()
    (BUILD/'source-artifact-sha256.json').write_text(json.dumps(dict(producer=producer,artifacts=expected,statuses=statuses),indent=2)+'\n')
    print('Production exact raw/shaded coverage, original identity, actual512 D32 PCF, palette, transfer, rings and repeated frame acceptance passed')
    print(json.dumps(statuses,indent=2))


if __name__=='__main__':main()
