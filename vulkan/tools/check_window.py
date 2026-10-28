#!/usr/bin/env python3
"""Drive only the spawned Vulkan window through X11 and retain app-only evidence."""
import argparse
import ctypes as C
import os
import contextlib
import select
import signal
import struct
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
U = C.c_ulong
I = C.c_int
P = C.c_void_p

class Client(C.Structure):
    _fields_ = [('type', I), ('serial', U), ('send_event', I), ('display', P), ('window', U),
                ('message_type', U), ('format', I), ('data', C.c_long * 5)]

class Input(C.Structure):
    _fields_ = [('type',I),('serial',U),('send_event',I),('display',P),('window',U),('root',U),('subwindow',U),('time',U),('x',I),('y',I),('x_root',I),('y_root',I),('state',C.c_uint),('code',C.c_uint),('same_screen',I)]

class Event(C.Union):
    _fields_ = [('client', Client), ('input', Input), ('pad', C.c_long * 24)]

class X11:
    def __init__(self):
        self.x = C.CDLL('libX11.so.6')
        signatures = {
            'XOpenDisplay': ([C.c_char_p], P), 'XDefaultRootWindow': ([P], U),
            'XQueryTree': ([P,U,C.POINTER(U),C.POINTER(U),C.POINTER(C.POINTER(U)),C.POINTER(C.c_uint)], I),
            'XFetchName': ([P,U,C.POINTER(C.c_char_p)], I), 'XFree': ([P], I),
            'XInternAtom': ([P,C.c_char_p,I], U),
            'XGetWindowProperty': ([P,U,U,C.c_long,C.c_long,I,U,C.POINTER(U),C.POINTER(I),C.POINTER(U),C.POINTER(U),C.POINTER(P)], I),
            'XSetInputFocus': ([P,U,I,U], I), 'XRaiseWindow': ([P,U], I),
            'XResizeWindow': ([P,U,C.c_uint,C.c_uint], I), 'XMapWindow': ([P,U], I),
            'XUnmapWindow': ([P,U], I), 'XFlush': ([P], I), 'XSync': ([P,I], I),
            'XKeysymToKeycode': ([P,U], C.c_ubyte),
            'XWarpPointer': ([P,U,U,I,I,C.c_uint,C.c_uint,I,I], I),
            'XSendEvent': ([P,U,I,C.c_long,C.POINTER(Event)], I), 'XCloseDisplay': ([P], I),
        }
        for name,(args,result) in signatures.items():
            fn = getattr(self.x,name); fn.argtypes=args; fn.restype=result
        self.d = self.x.XOpenDisplay(None)
        if not self.d:
            raise RuntimeError('A real DISPLAY is required for native-window verification')
        self.root = self.x.XDefaultRootWindow(self.d)
        self.pid_atom = self.x.XInternAtom(self.d,b'_NET_WM_PID',0)
        self.owned = None
        self.position=(0,0)

    def children(self, parent):
        root,parent_out,n = U(),U(),C.c_uint(); children=C.POINTER(U)()
        if not self.x.XQueryTree(self.d,parent,C.byref(root),C.byref(parent_out),C.byref(children),C.byref(n)):
            return []
        result = [children[j] for j in range(n.value)]
        if children: self.x.XFree(children)
        return result

    def title(self, window):
        value=C.c_char_p()
        self.x.XFetchName(self.d,window,C.byref(value))
        result=value.value.decode() if value else ''
        if value: self.x.XFree(value)
        return result

    def pid(self, window):
        actual,fmt,n,after,data=U(),I(),U(),U(),P()
        self.x.XGetWindowProperty(self.d,window,self.pid_atom,0,1,0,6,C.byref(actual),C.byref(fmt),C.byref(n),C.byref(after),C.byref(data))
        result = C.cast(data,C.POINTER(U))[0] if data and n.value else 0
        if data: self.x.XFree(data)
        return result

    def find(self, pid):
        stack = self.children(self.root)
        while stack:
            window = stack.pop()
            if self.pid(window)==pid:
                self.owned=window
                return window
            stack.extend(self.children(window))
        return None

    def flush(self): self.x.XSync(self.d,0)
    def focus(self):
        self.x.XRaiseWindow(self.d,self.owned)
        self.x.XSetInputFocus(self.d,self.owned,1,0)
        self.flush()
    def key(self, symbol, down):
        event=Event(); event.input.type=2 if down else 3; event.input.display=self.d
        event.input.window=self.owned; event.input.root=self.root; event.input.same_screen=1
        event.input.code=self.x.XKeysymToKeycode(self.d,symbol)
        self.x.XSendEvent(self.d,self.owned,0,1 if down else 2,C.byref(event)); self.flush()
    def tap(self, symbol):
        self.key(symbol,1); time.sleep(.04); self.key(symbol,0)
    def button(self, button, down):
        event=Event(); event.input.type=4 if down else 5; event.input.display=self.d
        event.input.window=self.owned; event.input.root=self.root; event.input.same_screen=1
        event.input.code=button; event.input.x=self.position[0]; event.input.y=self.position[1]
        self.x.XSendEvent(self.d,self.owned,0,4 if down else 8,C.byref(event)); self.flush()
    def move(self,x,y):
        self.position=(x,y)
        self.x.XWarpPointer(self.d,0,self.owned,0,0,0,0,x,y); self.flush()
    def moves(self,points):
        for x,y in points:
            self.position=(x,y)
            self.x.XWarpPointer(self.d,0,self.owned,0,0,0,0,x,y)
        self.flush()
    def resize(self,w,h):
        self.x.XResizeWindow(self.d,self.owned,w,h); self.flush()
    def map(self, mapped):
        getattr(self.x,'XMapWindow' if mapped else 'XUnmapWindow')(self.d,self.owned); self.flush()
    def close(self):
        event=Event(); event.client.type=33; event.client.display=self.d; event.client.window=self.owned
        event.client.message_type=self.x.XInternAtom(self.d,b'WM_PROTOCOLS',0); event.client.format=32
        event.client.data[0]=self.x.XInternAtom(self.d,b'WM_DELETE_WINDOW',0)
        self.x.XSendEvent(self.d,self.owned,0,0,C.byref(event)); self.flush()


def states(log):
    result=[]
    for line in log.read_text().split('\n')[:-1]:
        if line.startswith('STATE '):
            value={k: int(v) if v.isdigit() else v for k,v in re.findall(r'(\w+)=([^ ]+)',line)}
            if isinstance(value.get('camera'),str) and value['camera'].count(',')==4:
                result.append(value)
    return result


def run_product(binary):
    from PIL import Image
    log=BUILD/'window-product.log'
    env=dict(os.environ,VK_INSTANCE_LAYERS='VK_LAYER_KHRONOS_validation',VK_LAYER_VALIDATE_SYNC='1')
    x=X11()
    with log.open('w') as output:
        process=subprocess.Popen([str(binary)],cwd=ROOT,stdout=output,stderr=subprocess.STDOUT,env=env)
        def capture(name, expected=None, different=None):
            path=BUILD/f'window-product-{name}.png'
            deadline=time.monotonic()+12
            while time.monotonic()<deadline:
                assert process.poll() is None, log.read_text()[-6000:]
                subprocess.run(['import','-window',str(x.owned),str(path)],check=True,timeout=10)
                image=Image.open(path).convert('RGB')
                colors=image.getcolors(image.width*image.height)
                pixels=image.tobytes()
                if colors and len(colors)>3 and (expected is None or pixels==expected) and pixels!=different:
                    return pixels
                time.sleep(.1)
            raise AssertionError(f'{name}: ordinary product pixels did not reach the expected image')
        try:
            deadline=time.monotonic()+12
            while not x.find(process.pid):
                assert process.poll() is None, log.read_text()[-6000:]
                if time.monotonic()>deadline: raise AssertionError('Ordinary product window was not found')
                time.sleep(.05)
            x.focus()
            x.move(292,210); time.sleep(.35)
            intact=capture('intact')
            time.sleep(.2)
            assert capture('hover-settled') == intact
            x.button(1,1); x.button(1,0)
            carved=capture('click-carved',different=intact)
            x.tap(ord('r'))
            capture('reset',expected=intact,different=carved)
            x.map(False); time.sleep(.25)
            assert process.poll() is None, log.read_text()[-6000:]
            x.close(); process.wait(timeout=12)
            text=log.read_text()
            assert process.returncode==0, text[-6000:]
            assert not text.strip(), text
            assert not re.search(r'^(STATE|TIMING) ',text,re.MULTILINE), 'Default product emitted runtime diagnostics'
            assert 'Validation Error' not in text and 'SYNC-HAZARD' not in text, text
            print(f'Ordinary product default quiet, edit pixels, exact reset and suspended WM close passed. Evidence {log.relative_to(ROOT)}',flush=True)
        finally:
            if process.poll() is None:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
            x.x.XCloseDisplay(x.d)


def run(binary, split=False, suspended_close=False, escape=False):
    from PIL import Image
    suffix = ('split' if split else 'shared') + ('-suspended-close' if suspended_close else '')
    log=BUILD/f'window-{suffix}.log'
    env=dict(os.environ,VK_INSTANCE_LAYERS='VK_LAYER_KHRONOS_validation',VK_LAYER_VALIDATE_SYNC='1',ASAN_OPTIONS='detect_leaks=0',UBSAN_OPTIONS='halt_on_error=1')
    x=X11()
    with log.open('w') as output:
        process=subprocess.Popen([str(binary),'--cube','--trace',*(['--split'] if split else [])],cwd=ROOT,stdout=output,stderr=subprocess.STDOUT,env=env)
        def wait(predicate, message, timeout=12):
            deadline=time.monotonic()+timeout
            while time.monotonic()<deadline:
                values=states(log)
                if values and predicate(values[-1]): return values[-1]
                if process.poll() is not None:
                    raise AssertionError(f'{message}: process exited {process.returncode}\n{log.read_text()[-6000:]}')
                time.sleep(.04)
            raise AssertionError(f'{message}: timed out\n{log.read_text()[-4000:]}')
        def acquisitions():
            complete=log.read_text().rsplit('\n',1)[0]
            values=re.findall(r'COUNTS rows=\d+ allocations=\d+ acquisitions=(\d+)',complete)
            assert values, 'Native dispatch counters are required. Use --build.'
            return int(values[-1])
        def capture(name):
            path=BUILD/f'window-{suffix}-{name}.png'
            deadline=time.monotonic()+5
            while time.monotonic()<deadline:
                subprocess.run(['import','-window',str(x.owned),str(path)],check=True,timeout=10)
                image=Image.open(path).convert('RGB')
                colors=image.getcolors(image.width*image.height)
                if colors and len(colors)>3: return image.tobytes()
                time.sleep(.1)
            raise AssertionError(f'{name}: rendered window has no cube')
        def changed_capture(name, previous):
            deadline=time.monotonic()+8
            while time.monotonic()<deadline:
                pixels=capture(name)
                if pixels!=previous: return pixels
                time.sleep(.1)
            raise AssertionError(f'{name}: camera/model changed without changed window pixels')
        try:
            deadline=time.monotonic()+10
            while not x.find(process.pid):
                if time.monotonic()>deadline: raise AssertionError('Owned application window was not found')
                time.sleep(.05)
            x.focus(); x.button(3,0); x.button(1,0)
            before=wait(lambda s:s['frame']>=3,'Initial presentation')
            acquisitions()
            intact=capture('intact')
            x.key(ord('w'),1); time.sleep(.15); x.key(ord('w'),0)
            flown=wait(lambda s:s['camera']!=before['camera'] and s['frame']>before['frame']+2,'WASD flight')
            assert flown['uploads']==before['uploads'], 'Camera flight rebuilt the mesh'
            wait(lambda s:s['frame']>flown['frame']+2,'Flight presentation')
            flight_pixels=changed_capture('flight',intact)
            x.focus(); x.move(flown['width']//2,flown['height']//2); x.button(3,1)
            wait(lambda s:s['captured']==1,'RMB capture')
            os.kill(process.pid,signal.SIGSTOP)
            try: x.moves([(flown['width']//2+10,flown['height']//2+3),(flown['width']//2+22,flown['height']//2+9)])
            finally: os.kill(process.pid,signal.SIGCONT)
            before_yaw=struct.unpack('<f',struct.pack('<I',int(flown['camera'].split(',')[3])))[0]
            def full_look(state):
                after_yaw=struct.unpack('<f',struct.pack('<I',int(state['camera'].split(',')[3])))[0]
                return abs((before_yaw-after_yaw)-.066)<.00001
            looked=wait(full_look,'Queued pointer motion without loss or double counting')
            x.button(3,0); wait(lambda s:s['captured']==0 and s['frame']>looked['frame']+2,'Capture release')
            look_pixels=changed_capture('look',flight_pixels)
            assert looked['uploads']==before['uploads'], 'Look rebuilt mesh'
            x.move(looked['width']//2,looked['height']//2); x.button(1,1); x.button(1,0)
            carved=wait(lambda s:s['revision']>looked['revision'] and s['uploads']>looked['uploads'],'Click carving')
            wait(lambda s:s['frame']>carved['frame']+2,'Carved presentation')
            click_pixels=changed_capture('click-carved',look_pixels)
            x.tap(ord('r')); reset=wait(lambda s:s['quads']==384 and s['uploads']>carved['uploads'],'Reset')
            wait(lambda s:s['frame']>reset['frame']+2,'Reset presentation')
            reset_pixels=changed_capture('reset',click_pixels)
            assert reset_pixels==look_pixels, 'Reset did not restore the intact cube at the same camera'
            x.tap(32); demo=wait(lambda s:s['quads']==396 and s['uploads']>reset['uploads'],'Demo cut')
            wait(lambda s:s['frame']>demo['frame']+2,'Demo presentation'); changed_capture('demo-carved',reset_pixels)
            for width,height in [(800,450),(450,700),(720,480),(480,720),(800,450)]:
                old=states(log)[-1]; x.resize(width,height)
                resized=wait(lambda s:s['width']==width and s['height']==height and s['generation']>old['generation'] and s['frame']>old['frame']+2,'Non-square recreation')
                x.tap(ord('r')); clean=wait(lambda s:s['quads']==384 and s['uploads']>resized['uploads'],'Resized reset')
                wait(lambda s:s['frame']>clean['frame']+2,'Resized reset presentation')
                clean_pixels=capture(f'{width}x{height}-intact')
                x.move(width//2,height//2); x.button(1,1); x.button(1,0)
                edited=wait(lambda s:s['revision']>clean['revision'] and s['uploads']>clean['uploads'],'Extent-aware picking')
                wait(lambda s:s['frame']>edited['frame']+2,'Resized edit presentation')
                edited_pixels=changed_capture(f'{width}x{height}-carved',clean_pixels)
                x.tap(ord('r')); reset=wait(lambda s:s['quads']==384 and s['uploads']>edited['uploads'],'Resized reset after edit')
                wait(lambda s:s['frame']>reset['frame']+2,'Resized intact presentation')
                assert changed_capture(f'{width}x{height}-reset',edited_pixels)==clean_pixels, 'Resized reset did not restore the intact cube at the same camera'
            capture('resized')
            x.button(3,1); wait(lambda s:s['captured']==1,'Capture before focus loss')
            x.x.XSetInputFocus(x.d,x.root,1,0); x.flush()
            wait(lambda s:s['captured']==0,'Focus loss releases capture')
            x.focus(); x.map(False)
            suspended=wait(lambda s:s['mapped']==0,'Unmap suspension')
            suspended_acquisitions=acquisitions()
            time.sleep(.25); current=states(log)[-1]
            assert acquisitions()==suspended_acquisitions, 'Suspended app continued native acquisition dispatch'
            assert current['frame']<=suspended['frame']+2 and current['generation']==suspended['generation'], 'Suspended app continued acquisition/recreation'
            if not suspended_close:
                x.map(True); x.focus(); restored=wait(lambda s:s['mapped']==1 and s['frame']>current['frame']+2,'Restore')
                x.tap(ord('r')); wait(lambda s:s['quads']==384 and s['uploads']>restored['uploads'],'Input after restore')
                capture('restored')
            if escape: x.key(0xff1b,1)
            else: x.close()
            process.wait(timeout=12)
            text=log.read_text()
            assert process.returncode==0, text[-6000:]
            assert 'Native interactive shutdown rows=0' in text
            counts=[tuple(map(int,pair)) for pair in re.findall(r'COUNTS rows=(\d+) allocations=(\d+)',text)]
            assert counts, "Native allocation counters were not recorded"
            if counts:
                assert 'Native metadata allocations=0' in text
                assert max(rows for rows,allocs in counts)<100
                assert max(allocs for rows,allocs in counts)<300
                assert counts[-1]==(0,0)
            steady=[s['rows'] for s in states(log) if s['generation']>=1 and s['uploads']>=2]
            assert max(steady)-min(steady)<=16, 'Recreation or editing leaked rows'
            assert 'Validation Error' not in text and 'SYNC-HAZARD' not in text, text
            assert 'AddressSanitizer' not in text and 'runtime error:' not in text, text
            queues=re.search(r'Queues (\d+) (\d+)',text)
            assert queues and ((queues[1]!=queues[2]) if split else (queues[1]==queues[2]))
            print(f'Native window {suffix} passed. Evidence {log.relative_to(ROOT)}',flush=True)
        finally:
            if x.owned and process.poll() is None:
                x.button(3,0); x.button(1,0); x.key(ord("w"),0)
            if process.poll() is None:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
            x.x.XCloseDisplay(x.d)


def deduplicate_native(emitted):
    begin_marker='#ifndef BV_NATIVE_IMPLEMENTATION\n#define BV_NATIVE_IMPLEMENTATION\n'
    end_marker='#endif // BV_NATIVE_IMPLEMENTATION'
    first=emitted.find(begin_marker)
    if first<0: raise ValueError('Native module guard moved')
    start=emitted.find(begin_marker,first+len(begin_marker))
    while start>=0:
        end=emitted.index(end_marker,start)+len(end_marker)
        emitted=emitted[:start]+emitted[end:]
        start=emitted.find(begin_marker,first+len(begin_marker))
    return emitted


def instrument_window(emitted):
    marker='// Linux X11 window effects share the checked registry with native.c.'
    if marker not in emitted:
        return emitted
    begin=emitted.index(marker)
    end=emitted.index('static void __attribute__((constructor)) bv_window_register(void)',begin)
    window=emitted[begin:end]
    window=window.replace('malloc(','bv_test_alloc(').replace('calloc(','bv_test_calloc(').replace('realloc(','bv_test_realloc(')
    window=re.sub(r'\bfree\(','bv_test_free(',window)
    return emitted[:begin]+window+emitted[end:]


def build_window(sanitize=False, compile_timeout=None):
    BUILD.mkdir(exist_ok=True)
    source=BUILD/'voxel-interactive-probes.c'
    binary=BUILD/('voxel-interactive-sanitized' if sanitize else 'voxel-interactive-checked')
    subprocess.run(['bend','examples/voxel_interactive.bend','-o',str(source)],cwd=ROOT,check=True,timeout=compile_timeout)
    emitted=deduplicate_native(source.read_text())
    allocator=(ROOT/'../deps/bend-vulkan/tests/probes.c').read_text().split('static unsigned bv_test_barrier_calls;')[0]+'\nstatic uint64_t bv_test_acquisitions;\n'
    begin=emitted.index('// Bend native effect ABI.')
    end=emitted.index('static void __attribute__((constructor)) bv_register(void)',begin)
    native=emitted[begin:end]
    native=native.replace('malloc(', 'bv_test_alloc(').replace('calloc(', 'bv_test_calloc(').replace('realloc(', 'bv_test_realloc(')
    native=re.sub(r'\bfree\(', 'bv_test_free(',native)
    native=native.replace('static BvRow* bv_add(',allocator+'\nstatic BvRow* bv_add(',1)
    acquire_dispatch='uint32_t index=0;result=bv_device_result(owner,device->AcquireNextImageKHR('
    if native.count(acquire_dispatch)!=1: raise ValueError('Acquire dispatch moved')
    native=native.replace(acquire_dispatch,'uint32_t index=0;bv_test_acquisitions++;result=bv_device_result(owner,device->AcquireNextImageKHR(')
    a=native.index('static Term bv_live_objects(');b=native.index('\n}',a)
    check='  printf("COUNTS rows=%u allocations=%u acquisitions=%llu\\n",count,bv_test_live_allocations,(unsigned long long)bv_test_acquisitions);fflush(stdout);\n  if(!count) {assert(bv_test_live_allocations==0);puts("Native metadata allocations=0");fflush(stdout);}\n'
    native=native[:a]+native[a:b].replace('  return io_done(e,count);',check+'  return io_done(e,count);')+native[b:]
    source.write_text(instrument_window(emitted[:begin]+native+emitted[end:]))
    flags=['-fsanitize=address,undefined','-fno-omit-frame-pointer'] if sanitize else []
    subprocess.run(['clang','-std=c11','-O1','-g',*flags,str(source),'-lpthread','-lm','-ldl','-o',str(binary)],check=True,cwd=ROOT,timeout=compile_timeout)
    return binary

@contextlib.contextmanager
def isolated_display(enabled):
    if not enabled:
        yield
        return
    read_fd,write_fd=os.pipe()
    output=(BUILD/'window-xwayland.log').open('w')
    server=subprocess.Popen(['Xwayland','-displayfd',str(write_fd),'-geometry','1024x768','-noreset','-nolisten','tcp'],pass_fds=[write_fd],stdout=output,stderr=subprocess.STDOUT)
    os.close(write_fd)
    previous=os.environ.get('DISPLAY')
    try:
        if not select.select([read_fd],[],[],10)[0]: raise RuntimeError('Isolated Xwayland did not start')
        number=os.read(read_fd,64).decode().strip()
        if not number.isdigit(): raise RuntimeError('Isolated Xwayland returned no display')
        os.environ['DISPLAY']=':'+number
        yield
    finally:
        if previous is None: os.environ.pop('DISPLAY',None)
        else: os.environ['DISPLAY']=previous
        os.close(read_fd)
        server.terminate()
        try: server.wait(timeout=5)
        except subprocess.TimeoutExpired: server.kill(); server.wait()
        output.close()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',type=Path,help='reuse an instrumented binary, or an ordinary binary with --product')
    parser.add_argument('--product',action='store_true',help='build and check the ordinary executable without diagnostic flags')
    parser.add_argument('--build',action='store_true')
    parser.add_argument('--sanitize',action='store_true')
    parser.add_argument('--isolated-display',action='store_true',help='run a private rootful Xwayland server on the current Wayland desktop')
    parser.add_argument('--all',action='store_true',help='run shared queues, split queues, and suspended close sequentially')
    parser.add_argument('--split',action='store_true')
    parser.add_argument('--suspended-close',action='store_true')
    args=parser.parse_args()
    if not args.isolated_display and not os.environ.get('DISPLAY'): raise SystemExit('DISPLAY is required; use tools/verify.py for headless regression')
    BUILD.mkdir(exist_ok=True)
    if args.product:
        if args.all or args.split or args.suspended_close or args.sanitize or args.build:
            parser.error('--product requires the ordinary unsanitized executable without acceptance modifiers')
        binary=args.binary.resolve() if args.binary else BUILD/'voxel-interactive'
        if not args.binary:
            subprocess.run(['bend','examples/voxel_interactive.bend','-o',str(binary)],cwd=ROOT,check=True)
    else:
        binary=build_window(args.sanitize) if args.build or args.sanitize or args.binary is None else args.binary.resolve()
    with isolated_display(args.isolated_display):
        if args.product:
            run_product(binary)
        elif args.all:
            run(binary,False,False,escape=True)
            run(binary,True,False)
            run(binary,False,True)
        else:
            run(binary,args.split,args.suspended_close)

if __name__=='__main__': main()
