#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import subprocess

from check_window import isolated_display, ROOT, BUILD

COMPILE_TIMEOUT=1800


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--sanitize',action='store_true')
    parser.add_argument('--isolated-display',action='store_true')
    args=parser.parse_args()
    binary=BUILD/'milestone-6-acquisition'; source=binary.with_suffix('.c')
    commands=[]
    def run(command,name,env=None,timeout=180):
        result=subprocess.run(list(map(str,command)),cwd=ROOT,env=env,text=True,capture_output=True,timeout=timeout)
        (BUILD/f'milestone-6-acquisition-{name}.log').write_text(result.stdout+result.stderr)
        commands.append(dict(command=list(map(str,command)),status=result.returncode,log=name))
        (BUILD/'milestone-6-acquisition-commands.json').write_text(json.dumps(commands,indent=2)+'\n')
        assert result.returncode==0 and not any(m in result.stdout+result.stderr for m in ('SOME PROOFS FAIL','Validation Error','SYNC-HAZARD','AddressSanitizer','runtime error:')),name
        return result.stdout
    run(['bend','tests/appearance_acquisition.bend','-o',source],'bend-c',timeout=COMPILE_TIMEOUT)
    flags=['-fsanitize=address,undefined','-fno-omit-frame-pointer'] if args.sanitize else []
    run(['clang','-std=c11','-O1','-g',*flags,source,'-lpthread','-lm','-ldl','-o',binary],'compile',timeout=COMPILE_TIMEOUT)
    with isolated_display(args.isolated_display):
        output=run([binary], 'run',dict(os.environ,VK_INSTANCE_LAYERS='VK_LAYER_KHRONOS_validation',VK_LAYER_VALIDATE_SYNC='1',
                                       ASAN_OPTIONS='detect_leaks=0:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1'))
        assert 'matched device geometry plus all 2336 frame bytes' in output
        assert 'distinct camera and shadow readbacks passed' in output
        assert 'Actual completion observation order 2 then 1 retained completed_revision=2' in output
        assert 'Newer submitted slot waited for older present dispatch sequences zero then one' in output
        assert 'Same body revision camera packets obeyed actual submission order with two pending uniforms' in output
        assert 'Two obsolete submitted packets drained exact semaphore waits and acquisition leases' in output
        assert 'Presenting camera/pointer state survived completion and populated a later acquisition without mesh upload' in output
    print('Actual native acquisition-time edit/camera/hover and device geometry/frame bytes passed')


if __name__=='__main__':main()
