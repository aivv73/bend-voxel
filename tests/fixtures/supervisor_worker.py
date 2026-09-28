"""Controlled subprocesses for the public supervision boundary; never benchmarks."""
import ctypes
import json
import mmap
import os
from pathlib import Path
import signal
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'scripts'))
from megascene_inventory import SCHEMA


def record(kind, **fields):
    return {'schema':SCHEMA, 'record_type':kind, 'synthetic':True,
            **{k:os.environ['MEGASCENE_'+k.split('_')[0].upper()] for k in ('campaign_id','series_id','attempt_id')},
            'clock_id':'linux.CLOCK_MONOTONIC', 'time_ns':str(time.monotonic_ns()), **fields}


def heap():
    now = str(time.monotonic_ns())
    return {'record_type':'heap_sample', 'status':'measured', 'source':'synthetic', 'scope':'worker_process_driver_estimate',
            'device':'fixture', 'sample_begin_ns':now, 'sample_end_ns':now,
            'heaps':[{'heap':'0', 'flags':'1', 'usage_bytes':'0', 'budget_bytes':str(1024**3)}]}


def host(pid, case):
    now = str(time.monotonic_ns())
    value = {'record_type':'host_sample', 'status':'measured','source':'synthetic','scope':'process_tree/system/device_wide',
             'device':'fixture','sample_begin_ns':now,'sample_end_ns':now,'rss_bytes':'100',
             'available_ram_bytes':str(10*1024**3),'device_free_bytes':str(2*1024**3)}
    if pid or case == 'preflight_reserve':
        if case in ('rss','preflight_reserve'): value['rss_bytes'] = str(20*1024**3)
        if case == 'ram': value['available_ram_bytes'] = str(6*1024**3-1)
        if case == 'vram': value['device_free_bytes'] = str(768*1024**2-1)
        if case == 'malformed_monitor': value['rss_bytes']='not-an-integer'
        if case == 'monitor_error': value.update(status='collection_failure',reason='injected monitor error')
        if case == 'stale': value['sample_begin_ns'] = value['sample_end_ns'] = str(time.monotonic_ns()-2*10**9)
    return value


def main():
    mode, case = sys.argv[1:3]
    if mode == 'monitor':
        pid = int(sys.argv[3])
        while True:
            print(json.dumps(host(pid, case)),flush=True)
            if pid and case == 'monitor_exit': return 0
            if pid and case == 'monitor_hang': time.sleep(20)
            time.sleep(.05)
    fd = os.open(os.environ['MEGASCENE_REFERENCE'],os.O_RDWR)
    shared = mmap.mmap(fd,0); os.close(fd)
    lib = ctypes.CDLL(sys.argv[3])
    lib.commit.argtypes = [ctypes.c_void_p,ctypes.c_char_p,ctypes.c_size_t]
    address = ctypes.addressof(ctypes.c_char.from_buffer(shared))
    streams = {}
    counts = {}
    def write(name, kind, **fields):
        if name not in streams:
            streams[name] = open(os.environ['MEGASCENE_'+name], 'x', buffering=1)
            counts[name] = 0
        value = record(kind,sequence=str(counts[name]),**fields)
        streams[name].write(json.dumps(value)+'\n'); counts[name] += 1
        return value
    stop = threading.Event()
    def monitor_heaps():
        if case == 'missing_heap': return
        while not stop.is_set():
            value = heap()
            if case == 'heap': value['heaps'][0]['usage_bytes'] = str(1024**3)
            write('HEAPS',**dict(kind=value.pop('record_type'),**value))
            stop.wait(.05)
    thread = threading.Thread(target=monitor_heaps,daemon=True); thread.start()
    write('ALLOCATIONS','ledger_start',live_bytes='0',peak_bytes='0')
    while not Path(os.environ['MEGASCENE_GO']).exists(): time.sleep(.002)
    if case == 'startup': time.sleep(20)
    # The reference record uses the exact production commit implementation.
    now = time.monotonic_ns()
    for f in range(2):
        fields = dict(frame=str(f),begin_ns=str(now),end_ns=str(now+1),duration_ns='1',population='startup' if f == 0 else 'ordinary',
                      measured_ordinal=None if f == 0 else '0',status='measured',unit='ns')
        ref = record('frame',sequence=str(f),**fields)
        data = (json.dumps(ref)+'\n').encode()
        if case != 'lost_reference': lib.commit(address,data,len(data))
        write('EVENTS','frame',**fields)
        now += 1
    if case == 'actions':
        for index, kind in enumerate(('edit_begin','edit','action'),2):
            value = record(kind,sequence=str(index),frame='1',action='0',begin_ns=str(now),end_ns=str(now+1),
                           duration_ns='1',accepted=True,removed_cells='7')
            data = (json.dumps(value)+'\n').encode(); lib.commit(address,data,len(data))
    if case == 'overflow':
        for _ in range(1000): lib.commit(address,data,len(data))
    if case == 'reference_gap':
        shared[32:40] = (4).to_bytes(8,'little')
    if case == 'tail': streams['EVENTS'].write('{"damaged":')
    if case == 'allocation':
        write('ALLOCATIONS','allocation_failed',allocation_id='1',size_bytes='4096',memory_type='1',heap='0',device='fixture',
              live_bytes='0',peak_bytes='0',heap_live_bytes='0',heap_peak_bytes='0',vk_result='-2')
    if case == 'device_loss': write('ALLOCATIONS','vulkan_error',vk_result='-4',operation='injected')
    if case == 'crash': os.kill(os.getpid(),signal.SIGKILL)
    if case == 'external': os.kill(os.getppid(),signal.SIGTERM)
    if case in ('case','watchdog','external','campaign','monitor_hang','monitor_exit'): time.sleep(20)
    stop.set(); thread.join()
    for stream in streams.values(): stream.close()


if __name__ == '__main__':
    main()
