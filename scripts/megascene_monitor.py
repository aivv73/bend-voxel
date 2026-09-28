"""Isolated Linux/NVIDIA host monitor; blocking driver calls never block deadlines."""
import ctypes
import json
import os
from pathlib import Path
import sys
import time


def resident_tree(root, known=None):
    """Current process tree plus already discovered descendants, guarded by start ID.

    /proc is sampled, not an atomic snapshot. Exited processes contribute no
    current residency. Read/permission errors for live members are failures.
    """
    processes = {}
    for path in Path('/proc').iterdir():
        if not path.name.isdigit():
            continue
        try:
            fields = (path/'stat').read_text().rsplit(')', 1)[1].split()
            processes[int(path.name)] = (int(fields[1]), int(fields[2]), fields[19], int(fields[21]), fields[0])
        except (FileNotFoundError, ProcessLookupError):
            continue
    known = {} if known is None else known
    selected = {pid for pid,start in known.items() if pid in processes and processes[pid][2] == start}
    if root in processes and (root not in known or known[root] == processes[root][2]):
        selected.add(root)
    while True:
        children = {pid for pid, (parent, group, *_rest) in processes.items() if parent in selected or group == root}
        enlarged = selected | children
        if enlarged == selected:
            break
        selected = enlarged
    for pid in selected:
        if pid in processes:
            known[pid] = processes[pid][2]
    members = [{'pid': str(pid), 'start_ticks': processes[pid][2],
                'rss_bytes': str(processes[pid][3]*os.sysconf('SC_PAGE_SIZE'))}
               for pid in sorted(selected) if pid in processes and processes[pid][4] != 'Z']
    return sum(int(m['rss_bytes']) for m in members), members


class NVML:
    class Memory(ctypes.Structure):
        _fields_ = [(k, ctypes.c_ulonglong) for k in ('total', 'free', 'used')]

    def __init__(self, pci):
        self.lib = ctypes.CDLL('libnvidia-ml.so.1')
        self.check(self.lib.nvmlInit_v2())
        self.handle = ctypes.c_void_p()
        self.check(self.lib.nvmlDeviceGetHandleByPciBusId_v2(pci.encode(), ctypes.byref(self.handle)))
        name = ctypes.create_string_buffer(96)
        self.check(self.lib.nvmlDeviceGetUUID(self.handle, name, len(name)))
        self.uuid = name.value.decode()

    @staticmethod
    def check(code):
        if code:
            raise OSError(f'NVML collection failed: {code}')

    def free(self):
        result = self.Memory()
        self.check(self.lib.nvmlDeviceGetMemoryInfo(self.handle, ctypes.byref(result)))
        return result.free


def host_sample(pid, pci, nvml, known=None):
    begin = time.monotonic_ns()
    rss, members = resident_tree(pid, known) if pid else (0, [])
    mem = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
    available = int(mem['MemAvailable'].split()[0])*1024
    free = nvml.free()
    return {'record_type': 'host_sample', 'status': 'measured', 'unit': 'bytes',
            'source': 'linux.proc+NVML', 'scope': 'process_tree/system/device_wide',
            'rss_definition':'sum of current member RSS; shared pages may be counted per process',
            'device': pci, 'device_uuid': nvml.uuid, 'rss_bytes': str(rss), 'members': members,
            'available_ram_bytes': str(available), 'device_free_bytes': str(free),
            'sample_begin_ns': str(begin), 'sample_end_ns': str(time.monotonic_ns())}


def main():
    # Stream line-buffered through a pipe owned and persisted by the supervisor.
    pid, pci = int(sys.argv[1]), sys.argv[2]
    try:
        monitor = NVML(pci)
        target = time.monotonic()
        known = {}
        while True:
            print(json.dumps(host_sample(pid, pci, monitor, known), separators=(',', ':')), flush=True)
            target += .1
            time.sleep(max(0, target-time.monotonic()))
    except Exception as error:
        print(json.dumps({'record_type': 'monitor_error', 'status': 'collection_failure',
                          'reason': str(error), 'time_ns': str(time.monotonic_ns())}), flush=True)
        return 2


if __name__ == '__main__':
    sys.exit(main())
