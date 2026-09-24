#ifndef VOXEL_VULKAN_BRIDGE_C
#define VOXEL_VULKAN_BRIDGE_C
#if !defined(__linux__)
#error The Vulkan backend currently supports Linux/X11 only.
#endif

#include <dlfcn.h>
#include <time.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>

#ifndef BendWin
#define BendWin BendWin
typedef struct {
  Display* dpy;
  Window win;
  Atom del;
  XImage* img;
  u32 n, cap;
  u32* evs;
} BendWin;
#endif

typedef struct {
  u32 index, side, length, rows, owner;
  float offset;
} VoxelVkFace;
typedef struct {
  float eye[3], yaw, pitch, aim[3];
  u32 aim_kind, face_count;
  const VoxelVkFace* faces;
  const char* hud;
} VoxelVkFrame;
typedef struct {
  u32 geometry_us, fence_wait_us, vertex_upload_us, acquire_us;
  u32 command_record_us, submit_present_us;
} VoxelVkTimings;

typedef int (*VoxelVkRender)(void*, unsigned long, const VoxelVkFrame*, VoxelVkTimings*, char*, size_t);
typedef void (*VoxelVkRelease)(void);
static void* voxel_vk_library;
static VoxelVkRender voxel_vk_render_fn;
static VoxelVkRelease voxel_vk_release_fn;
static VoxelVkFace* voxel_vk_faces;
static u32 voxel_vk_capacity;

static u64 voxel_vk_tick(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (u64)now.tv_sec * 1000000000ull + (u64)now.tv_nsec;
}

static void voxel_vk_load(void) {
  if (voxel_vk_library) return;
  const char* path = getenv("VOXEL_VULKAN_LIBRARY");
  voxel_vk_library = dlopen(path ? path : "./build/libvoxel_vulkan.so", RTLD_NOW | RTLD_LOCAL);
  if (!voxel_vk_library) err_fail(dlerror());
  voxel_vk_render_fn = (VoxelVkRender)dlsym(voxel_vk_library, "voxel_vk_render");
  voxel_vk_release_fn = (VoxelVkRelease)dlsym(voxel_vk_library, "voxel_vk_release");
  if (!voxel_vk_render_fn || !voxel_vk_release_fn) err_fail("incomplete Vulkan renderer library");
}

static float voxel_vk_float(Term t) {
  u32 bits = (u32)t;
  float out;
  memcpy(&out, &bits, sizeof out);
  return out;
}

static void voxel_vk_append(VoxelVkFace face, u32* count) {
  if (*count >= 50000) err_fail("Vulkan face limit exceeded");
  if (*count == voxel_vk_capacity) {
    voxel_vk_capacity = voxel_vk_capacity ? voxel_vk_capacity * 2 : 512;
    voxel_vk_faces = io_mem(realloc(voxel_vk_faces, voxel_vk_capacity * sizeof *voxel_vk_faces));
  }
  voxel_vk_faces[(*count)++] = face;
}

static VoxelVkFrame voxel_vk_scene(Env e, Term state, Term aim, const char* hud) {
  if (term_aux(state) != CID_DEMO_STATE || term_aux(aim) != CID_RENDER_AIM)
    err_fail("bad Vulkan scene state");
  // Bend flattens nested Data fields in Type constructors. With the pinned
  // compiler, State is World(6), Control(Camera(5) + 9), pending, last.
  if (cid_arity(CID_DEMO_STATE)!=22 || cid_arity(CID_WORLD_WORLD)!=6 ||
      cid_arity(CID_INPUT_CONTROL)!=14 || cid_arity(CID_RENDER_AIM)!=5 ||
      cid_arity(CID_WORLD_BODY)!=5 || cid_arity(CID_WORLD_FACE)!=4)
    err_fail("Bend Vulkan state layout changed");
  Loc st = term_peek(e, state);
  Loc al = term_peek(e, aim);
  VoxelVkFrame frame = {0};
  for (u32 i=0;i<3;i+=1) {
    frame.eye[i]=voxel_vk_float(e.mem[st+6+i]);
    frame.aim[i]=voxel_vk_float(e.mem[al+i]);
  }
  frame.yaw = voxel_vk_float(e.mem[st+9]);
  frame.pitch = voxel_vk_float(e.mem[st+10]);
  frame.aim_kind = (u32)e.mem[al+4];
  frame.hud = hud;
  Term bodies = e.mem[st+1];
  while (term_aux(bodies) == CID_CON) {
    Loc cell = term_peek(e, bodies);
    Term body = e.mem[cell];
    if (term_aux(body) != CID_WORLD_BODY) err_fail("bad Vulkan body");
    Loc at = term_peek(e, body);
    u32 owner = (u32)e.mem[at];
    float offset = voxel_vk_float(e.mem[at + 1]);
    Term faces = e.mem[at + 4];
    while (term_aux(faces) == CID_CON) {
      Loc link = term_peek(e, faces);
      Term face = e.mem[link];
      if (term_aux(face) != CID_WORLD_FACE) err_fail("bad Vulkan face");
      Loc fl = term_peek(e, face);
      voxel_vk_append((VoxelVkFace){(u32)e.mem[fl], (u32)e.mem[fl + 1],
        (u32)e.mem[fl + 2], (u32)e.mem[fl + 3], owner, offset}, &frame.face_count);
      faces = e.mem[link + 1];
    }
    if (term_aux(faces) != CID_NIL) err_fail("bad Vulkan face list");
    bodies = e.mem[cell + 1];
  }
  if (term_aux(bodies) != CID_NIL) err_fail("bad Vulkan body list");
  frame.faces = voxel_vk_faces;
  return frame;
}

static const u32 voxel_vk_keys[][2] = {
  {XK_Escape,27},{XK_Return,13},{XK_KP_Enter,13},{XK_Tab,9},
  {XK_BackSpace,127},{XK_Up,63232},{XK_Down,63233},{XK_Left,63234},
  {XK_Right,63235},{XK_Insert,63271},{XK_Delete,63272},{XK_Home,63273},
  {XK_End,63275},{XK_Page_Up,63276},{XK_Page_Down,63277},
};
static u32 voxel_vk_key(XKeyEvent* ev) {
  char chars[8]; KeySym sym = 0;
  ev->state &= ShiftMask | LockMask;
  int n = XLookupString(ev, chars, sizeof chars, &sym, NULL);
  for (u32 i = 0; i < sizeof voxel_vk_keys / sizeof *voxel_vk_keys; i += 1)
    if (voxel_vk_keys[i][0] == sym) return voxel_vk_keys[i][1];
  if (n == 1 && (u8)chars[0] >= 32)
    return (u8)chars[0] >= 'A' && (u8)chars[0] <= 'Z' ? (u8)chars[0] + 32 : (u8)chars[0];
  return 65536 + ev->keycode;
}
static u32 voxel_vk_clip(int v, u32 bound) {
  return v < 0 ? 0 : (u32)v < bound ? (u32)v : bound - 1;
}
static u32 voxel_vk_pointer(int value, int extent, u32 logical) {
  return voxel_vk_clip(extent>0 ? (int)((int64_t)value*logical/extent) : value, logical);
}
static void voxel_vk_push(BendWin* win, u32 kind, u32 a, u32 b, u32 c, u32 d) {
  if (win->n == win->cap) {
    win->cap = win->cap ? win->cap * 2 : 64;
    win->evs = io_mem(realloc(win->evs, win->cap * 20));
  }
  u32 ev[5] = {kind,a,b,c,d};
  memcpy(win->evs + win->n * 5, ev, sizeof ev);
  win->n += 1;
}
static void voxel_vk_pump(BendWin* win) {
  u32 width = win->img->width, height = win->img->height;
  XWindowAttributes attributes;
  XGetWindowAttributes(win->dpy,win->win,&attributes);
  XSelectInput(win->dpy, win->win, KeyPressMask | KeyReleaseMask | ButtonPressMask |
    ButtonReleaseMask | PointerMotionMask | FocusChangeMask | LeaveWindowMask |
    StructureNotifyMask);
  while (XPending(win->dpy) > 0) {
    XEvent ev; XNextEvent(win->dpy, &ev);
    if (ev.type == KeyPress || ev.type == KeyRelease) {
      voxel_vk_push(win, 0, voxel_vk_key(&ev.xkey), ev.type == KeyPress, 0, 0);
    } else if (ev.type == ButtonPress || ev.type == ButtonRelease) {
      u32 b = ev.xbutton.button;
      if (b >= 1 && b <= 3) voxel_vk_push(win, 1,
        voxel_vk_pointer(ev.xbutton.x,attributes.width,width),
        voxel_vk_pointer(ev.xbutton.y,attributes.height,height),
        b == 1 ? 0 : 4 - b, ev.type == ButtonPress);
    } else if (ev.type == MotionNotify) {
      voxel_vk_push(win, 2, voxel_vk_pointer(ev.xmotion.x,attributes.width,width),
        voxel_vk_pointer(ev.xmotion.y,attributes.height,height), 0, 0);
    } else if (ev.type == FocusOut || ev.type == LeaveNotify) {
      voxel_vk_push(win, 0, 0, 0, 0, 0);
    } else if (ev.type == ClientMessage && (Atom)ev.xclient.data.l[0] == win->del) {
      voxel_vk_push(win, 3, 0, 0, 0, 0);
    }
  }
}
static Term voxel_vk_event(Env e, const u32* ev) {
  if (ev[0] == 3) return term_pak(CID_CLOSE, 0);
  u32 cid = ev[0] == 0 ? CID_KEY : ev[0] == 1 ? CID_MOUSE : CID_MOVE;
  u32 count = ev[0] == 1 ? 4 : 2;
  Loc at = heap_alloc(e, cls_fit(count));
  for (u32 i = 0; i < count; i += 1) e.mem[at + i] = ev[i + 1];
  return term_ctr(cid, at);
}
static Term voxel_vk_events(Env e, BendWin* win) {
  Term list = term_pak(CID_NIL, 0);
  for (u32 i = win->n; i > 0;) {
    i -= 1;
    Loc at = heap_alloc(e, 1);
    e.mem[at] = io_seal(e, voxel_vk_event(e, win->evs + 5 * i), CID_CON);
    e.mem[at + 1] = io_seal(e, list, CID_CON);
    list = term_ctr(CID_CON, at);
  }
  win->n = 0;
  return list;
}

Term vulkan_frame_run(Env e, Term* f, IoWork* work) {
  const char* bench = getenv("VOXEL_BENCH");
  int profile = bench && strcmp(bench, "1") == 0;
  u64 start = profile ? voxel_vk_tick() : 0;
  io_sync();
  voxel_vk_load();
  BendWin* win = (BendWin*)(intptr_t)io_hand_v(f[0]);
  u64 len = 0;
  char* hud = io_cstr(e, f[3], &len);
  VoxelVkFrame frame = voxel_vk_scene(e, f[1], f[2], hud);
  static int stress_scene_logged;
  if (getenv("VOXEL_STRESS_SCENE") && !stress_scene_logged++)
    fprintf(stdout,"surface,%u\n",frame.face_count);
  static u32 trace_frames;
  if (getenv("VOXEL_VULKAN_TRACE") && trace_frames++<10)
    fprintf(stderr,"vulkan frame eye %.3f %.3f %.3f yaw %.3f pitch %.3f faces %u aim %u\n",
      frame.eye[0],frame.eye[1],frame.eye[2],frame.yaw,frame.pitch,frame.face_count,frame.aim_kind);
  char error[512] = {0};
  u64 prepared = profile ? voxel_vk_tick() : 0;
  VoxelVkTimings timings = {0};
  int ok = voxel_vk_render_fn(win->dpy, win->win, &frame, &timings, error, sizeof error);
  if (!ok) err_fail(error[0] ? error : "Vulkan frame failed");
  u64 rendered = profile ? voxel_vk_tick() : 0;
  free(hud);
  voxel_vk_pump(win);
  XSync(win->dpy, False);
  Term events = voxel_vk_events(e, win);
  if (profile) {
    u64 ended = voxel_vk_tick();
    u64 render_us = (rendered - prepared) / 1000;
    u64 detailed = (u64)timings.geometry_us + timings.fence_wait_us +
      timings.vertex_upload_us + timings.acquire_us + timings.command_record_us +
      timings.submit_present_us;
    static u32 profile_frame;
    fprintf(stdout, "vulkan_stage,%u,%llu,%u,%u,%u,%u,%u,%u,%llu,%llu\n",
      profile_frame++, (unsigned long long)((prepared - start) / 1000),
      timings.geometry_us, timings.fence_wait_us, timings.vertex_upload_us,
      timings.acquire_us, timings.command_record_us, timings.submit_present_us,
      (unsigned long long)(render_us >= detailed ? render_us - detailed : 0),
      (unsigned long long)((ended - rendered) / 1000));
  }
  return io_tup(e, f[0], io_tup(e, f[1], events));
}

Term vulkan_release_run(Env e, Term* f, IoWork* work) {
  if (voxel_vk_release_fn) voxel_vk_release_fn();
  if (voxel_vk_library) dlclose(voxel_vk_library);
  voxel_vk_library = NULL;
  voxel_vk_render_fn = NULL;
  voxel_vk_release_fn = NULL;
  free(voxel_vk_faces);
  voxel_vk_faces = NULL;
  voxel_vk_capacity = 0;
  return f[0];
}

static void __attribute__((constructor)) voxel_vk_effects(void) {
  io_eff(CID_VULKAN_FRAME, vulkan_frame_run, 0);
  io_eff(CID_VULKAN_RELEASE, vulkan_release_run, 0);
}
#endif
