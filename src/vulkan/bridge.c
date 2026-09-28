#ifndef VOXEL_VULKAN_BRIDGE_C
#define VOXEL_VULKAN_BRIDGE_C
#if !defined(__linux__)
#error The Vulkan backend currently supports Linux/X11 only.
#endif

#include <dlfcn.h>
#include <math.h>
#include <time.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>

typedef struct {
  float lo[3], hi[3];  // Integer cell coordinates; zero thickness on side / 2.
  u32 side, material;
} VoxelVkFace;

typedef struct {
  float position[3];
  u32 side, material;
} VoxelVkVertex;

typedef struct {
  u32 id, revision, anchored, face_count;
  float offset, lo[3], hi[3];
  const VoxelVkFace* faces;
  u32 vertex_count;
  const VoxelVkVertex* vertices;
} VoxelVkBody;

typedef struct {
  float eye[3], yaw, pitch, aim[3];
  u32 aim_kind, body_count, night, width, height;
  const VoxelVkBody* bodies;
  const char* hud;
  float colors[19][3]; // Material pairs, linear surfaces, display overlays.
  // Additive explicit profile; zero retains the Light Atelier defaults.
  unsigned full_geometry;
  float ground_half_extent;
  void (*record)(const char* fields); // Megascene CPU evidence, NULL for legacy.
  uint64_t evidence_frame;
  unsigned gpu_evidence;
} VoxelVkFrame;

// Checkpoint-only ABI: independently read tree leaves and current Bend geometry.
typedef struct { float lo[3], hi[3]; uint32_t material; } VoxelMegaBox;
typedef struct {
  float speed;
  uint32_t box_count;
  const VoxelMegaBox* boxes;
  uint64_t tree_nodes;
} VoxelMegaBody;
typedef struct {
  const VoxelMegaBody* bodies;
  uint32_t world[6]; // cells, fragments, removed, status, next ID, budget
  float aim_radius;
  uint64_t frame;
  uint32_t warmup, measured;
  const char* schedule_sha256;
} VoxelMegaState;

typedef struct {
  u32 geometry_us, fence_wait_us, vertex_upload_us, acquire_us;
  u32 command_record_us, submit_present_us;
} VoxelVkTimings;

typedef int (*VoxelVkRender)(void*, unsigned long, const VoxelVkFrame*, VoxelVkTimings*, char*, size_t);
typedef void (*VoxelVkRelease)(void);
static void* voxel_vk_library;
static VoxelVkRender voxel_vk_render_fn;
static VoxelVkRelease voxel_vk_release_fn;
// Bend owns the world and builds body vertices. Copy both cached surface
// representations only when geometry changes; camera and motion reuse them.
typedef struct {
  VoxelVkFace* faces;
  VoxelVkVertex* vertices;
  u32 revision, count, vertex_count, seen, valid;
} VoxelVkTransport;
static VoxelVkTransport* voxel_vk_cache;
static u32 voxel_vk_cache_capacity, voxel_vk_generation;
static VoxelVkBody* voxel_vk_bodies;
static u32 voxel_vk_capacity;
static float voxel_vk_colors[19][3];
static int voxel_vk_colors_ready;

static u64 voxel_vk_tick(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now)) err_fail("monotonic clock failed");
  return (u64)now.tv_sec * 1000000000ull + (u64)now.tv_nsec;
}

// The marker effect is emitted before window creation in the static worker.
// Keep it independent of Base's window effect ordering. Legacy workers have
// no recorder and retain their original execution path.
static FILE* mega_stream;
static u64 mega_frame,mega_previous_end;
static u32 mega_warmup,mega_measured;
static float mega_ground;
#ifdef CID_VULKAN_VULKAN_MARK
static void mega_record(const char* fields);
static void mega_reference(const char* fields);
static void mega_stage(const char* name,u64 begin,u64 end);
static const char* mega_env(const char* name);
#else
static void mega_record(const char* fields) { (void)fields; }
static void mega_reference(const char* fields) { (void)fields; }
static void mega_stage(const char* name,u64 begin,u64 end) { (void)name; (void)begin; (void)end; }
#endif
#ifdef CID_VULKAN_VULKAN_CAPTURE
Term vulkan_capture_run(Env e, Term* f, IoWork* work) {
  const char* directory=getenv("MEGASCENE_CAPTURE_DIR");
  char path[4096];
  if (directory) {
    u64 rendered=mega_frame-1;
    int review=rendered==0 || rendered==(u64)mega_warmup+mega_measured ||
      (rendered>mega_warmup && (rendered-mega_warmup-1)%300==60);
    if (!review) return f[0];
    if (snprintf(path,sizeof path,"%s/frame-%04llu.ppm",directory,(unsigned long long)rendered)>=(int)sizeof path)
      err_fail("capture path too long");
  }
  BendWin* win=(BendWin*)(intptr_t)io_hand_v(f[0]);
  if (directory) usleep(250000); // Validation captures are outside measured samples.
  XSync(win->dpy,False);
  unsigned width=win->img->width,height=win->img->height;
  XImage* image=XGetImage(win->dpy,win->win,0,0,width,height,AllPlanes,ZPixmap);
  if (!image) err_fail("opening capture unavailable");
  FILE* file=fopen(directory?path:mega_env("MEGASCENE_CAPTURE"),"wx");
  if (!file) err_fail("cannot create opening capture");
  fprintf(file,"P6\n%u %u\n255\n",width,height);
  unsigned long masks[]={image->red_mask,image->green_mask,image->blue_mask};
  for (unsigned y=0;y<height;y++) for (unsigned x=0;x<width;x++) {
    unsigned long pixel=XGetPixel(image,x,y);
    for (unsigned c=0;c<3;c++) {
      unsigned long mask=masks[c],value=pixel&mask;
      if (!mask) err_fail("unsupported capture channel mask");
      while (!(mask&1)) { mask>>=1; value>>=1; }
      if (fputc((int)(value*255/mask),file)==EOF) err_fail("capture write failed");
    }
  }
  XDestroyImage(image);
  if (fclose(file)) err_fail("capture flush failed");
  if (directory) {
    char record[128];
    snprintf(record,sizeof record,"\"record_type\":\"capture\",\"rendered_frame\":\"%llu\"",(unsigned long long)(mega_frame-1));
    mega_record(record);
  } else mega_record("\"record_type\":\"opening_capture\"");
  return f[0];
}

#endif

static void voxel_vk_load(void) {
  if (voxel_vk_library) return;
  const char* path = getenv("VOXEL_VULKAN_LIBRARY");
  voxel_vk_library = dlopen(path ? path : "./build/libvoxel_vulkan.so", RTLD_NOW | RTLD_LOCAL);
  if (!voxel_vk_library) err_fail(dlerror());
  voxel_vk_render_fn = (VoxelVkRender)dlsym(voxel_vk_library, "voxel_vk_render_timed");
  voxel_vk_release_fn = (VoxelVkRelease)dlsym(voxel_vk_library, "voxel_vk_release");
  if (!voxel_vk_render_fn || !voxel_vk_release_fn) err_fail("incomplete Vulkan renderer library");
}

static float voxel_vk_float(Term t) {
  u32 bits = (u32)t;
  float out;
  memcpy(&out, &bits, sizeof out);
  return out;
}

static void voxel_vk_read_transport(VoxelVkTransport* entry,u32 revision,Env e,Term faces,Term vertices) {
  free(entry->faces); entry->faces=NULL; entry->count=0;
  free(entry->vertices); entry->vertices=NULL; entry->vertex_count=0;
  size_t capacity=0;
  while (term_aux(faces)==CID_CON) {
    u64 link=term_peek(e.mem,faces);
    Term face=e.mem[link];
    if (term_aux(face)!=CID_SPATIAL_FACE) err_fail("bad Vulkan face");
    u64 at=term_peek(e.mem,face);
    if (entry->count==capacity) {
      capacity=capacity ? capacity*2 : 64;
      if (capacity>UINT32_MAX) err_fail("Vulkan face count overflow");
      entry->faces=io_mem(realloc(entry->faces,capacity*sizeof *entry->faces));
    }
    VoxelVkFace* out=&entry->faces[entry->count++];
    for (u32 i=0;i<3;i++) {
      out->lo[i]=voxel_vk_float(e.mem[at+i]);
      out->hi[i]=voxel_vk_float(e.mem[at+3+i]);
    }
    out->side=(u32)e.mem[at+6]; out->material=(u32)e.mem[at+7];
    faces=e.mem[link+1];
  }
  if (term_aux(faces)!=CID_NIL) err_fail("bad Vulkan face list");
  capacity=0;
  while (term_aux(vertices)==CID_CON) {
    u64 link=term_peek(e.mem,vertices);
    Term vertex=e.mem[link];
    if (term_aux(vertex)!=CID_MESH_VERTEX) err_fail("bad Bend mesh vertex");
    u64 at=term_peek(e.mem,vertex);
    if (entry->vertex_count==capacity) {
      capacity=capacity ? capacity*2 : 64;
      if (capacity>UINT32_MAX) err_fail("Vulkan vertex count overflow");
      entry->vertices=io_mem(realloc(entry->vertices,capacity*sizeof *entry->vertices));
    }
    VoxelVkVertex* out=&entry->vertices[entry->vertex_count++];
    for (u32 i=0;i<3;i++) out->position[i]=voxel_vk_float(e.mem[at+i]);
    out->side=(u32)e.mem[at+3]; out->material=(u32)e.mem[at+4];
    vertices=e.mem[link+1];
  }
  if (term_aux(vertices)!=CID_NIL || entry->vertex_count!=(size_t)entry->count*6)
    err_fail("bad Bend mesh vertex list");
  entry->revision=revision; entry->valid=1;

}

static VoxelVkTransport* voxel_vk_transport(u32 id, u32 revision, Env e, Term faces, Term vertices) {
  if (id >= voxel_vk_cache_capacity) {
    u32 previous=voxel_vk_cache_capacity;
    size_t capacity=previous ? previous : 256;
    while (id >= capacity) capacity*=2;
    if (capacity>UINT32_MAX) err_fail("Vulkan body ID overflow");
    voxel_vk_cache=io_mem(realloc(voxel_vk_cache,capacity*sizeof *voxel_vk_cache));
    memset(voxel_vk_cache+previous,0,(capacity-previous)*sizeof *voxel_vk_cache);
    voxel_vk_cache_capacity=(u32)capacity;
  }
  VoxelVkTransport* entry=&voxel_vk_cache[id];
  entry->seen=voxel_vk_generation;
  if (entry->valid && entry->revision==revision) return entry;
  voxel_vk_read_transport(entry,revision,e,faces,vertices);
  return entry;
}

static void voxel_vk_palette(Env e, Term colors) {
  if (cid_arity(CID_MATH_VEC)!=3) err_fail("Bend palette vector layout changed");
  for (u32 color=0;color<19;color++) {
    if (term_aux(colors)!=CID_CON) err_fail("incomplete Bend color palette");
    u64 link=term_peek(e.mem,colors);
    Term vector=e.mem[link];
    if (term_aux(vector)!=CID_MATH_VEC) err_fail("bad Bend palette color");
    u64 at=term_peek(e.mem,vector);
    for (u32 channel=0;channel<3;channel++) {
      float value=voxel_vk_float(e.mem[at+channel]);
      if (!isfinite(value) || value<0 || value>1) err_fail("invalid Bend palette color");
      voxel_vk_colors[color][channel]=value;
    }
    colors=e.mem[link+1];
  }
  if (term_aux(colors)!=CID_NIL) err_fail("extra Bend palette colors");
  voxel_vk_colors_ready=1;
}

#ifdef CID_VULKAN_VULKAN_MARK
static VoxelMegaBox mega_tree(Env e,Term tree,VoxelMegaBox** boxes,u32* count,u64* nodes,unsigned depth) {
  if(depth>128) err_fail("checkpoint tree depth exceeded");
  u32 kind=term_aux(tree);
  if(kind!=CID_SPATIAL_LEAF&&kind!=CID_SPATIAL_BRANCH) err_fail("checkpoint empty tree child");
  u64 at=term_peek(e.mem,tree); VoxelMegaBox box;
  (*nodes)++;
  for(unsigned k=0;k<3;k++) {
    box.lo[k]=voxel_vk_float(e.mem[at+k]); box.hi[k]=voxel_vk_float(e.mem[at+3+k]);
    if(!isfinite(box.lo[k])||!isfinite(box.hi[k])||box.lo[k]>=box.hi[k]) err_fail("checkpoint invalid tree bounds");
  }
  box.material=(u32)e.mem[at+6];
  if(kind==CID_SPATIAL_LEAF) {
    if(*count==UINT32_MAX) err_fail("checkpoint cuboid count overflow");
    *boxes=io_mem(realloc(*boxes,((size_t)*count+1)*sizeof **boxes)); (*boxes)[(*count)++]=box;
  } else {
    VoxelMegaBox a=mega_tree(e,e.mem[at+7],boxes,count,nodes,depth+1);
    VoxelMegaBox b=mega_tree(e,e.mem[at+8],boxes,count,nodes,depth+1);
    if(box.material) err_fail("checkpoint branch material");
    for(unsigned k=0;k<3;k++) if(box.lo[k]!=fminf(a.lo[k],b.lo[k])||box.hi[k]!=fmaxf(a.hi[k],b.hi[k]))
      err_fail("checkpoint tree summary mismatch");
  }
  return box;
}
static void voxel_mega_check(Env e,u64 st,u64 al,const VoxelVkFrame* frame) {
  int validation=getenv("MEGASCENE_VALIDATE")!=NULL;
  int review=getenv("MEGASCENE_CAMERA_FILE") && mega_frame>mega_warmup &&
    (mega_frame-mega_warmup-1)%300==60;
  if(!validation&&!review&&mega_frame!=0&&mega_frame!=mega_warmup&&mega_frame!=(u64)mega_warmup+mega_measured) return;
  u64 begin=voxel_vk_tick();
  VoxelMegaBody* raw=io_mem(calloc(frame->body_count,sizeof *raw));
  VoxelVkBody* actual=io_mem(calloc(frame->body_count,sizeof *actual));
  Term bodies=e.mem[st];
  for(u32 i=0;i<frame->body_count;i++) {
    if(term_aux(bodies)!=CID_CON) err_fail("checkpoint body list changed");
    u64 link=term_peek(e.mem,bodies),at=term_peek(e.mem,e.mem[link]);
    VoxelMegaBox* boxes=NULL; u64 nodes=0;
    mega_tree(e,e.mem[at+5],&boxes,&raw[i].box_count,&nodes,0);
    raw[i].boxes=boxes; raw[i].tree_nodes=nodes; raw[i].speed=voxel_vk_float(e.mem[at+3]);
    VoxelVkTransport fresh={0};
    voxel_vk_read_transport(&fresh,frame->bodies[i].revision,e,e.mem[at+6],e.mem[at+7]);
    actual[i]=frame->bodies[i];
    if(fresh.count!=actual[i].face_count||fresh.vertex_count!=actual[i].vertex_count||
       memcmp(fresh.faces,actual[i].faces,fresh.count*sizeof *fresh.faces)||
       memcmp(fresh.vertices,actual[i].vertices,fresh.vertex_count*sizeof *fresh.vertices))
      err_fail("checkpoint stale native transport");
    actual[i].faces=fresh.faces; actual[i].vertices=fresh.vertices;
    bodies=e.mem[link+1];
  }
  VoxelMegaState state={0}; state.bodies=raw; state.frame=mega_frame;
  for(unsigned i=0;i<6;i++) state.world[i]=(u32)e.mem[st+1+i];
  state.aim_radius=voxel_vk_float(e.mem[al+3]); state.warmup=mega_warmup; state.measured=mega_measured;
  state.schedule_sha256=mega_env("MEGASCENE_SCHEDULE_SHA256");
  voxel_vk_load();
  typedef int (*Check)(const VoxelVkFrame*,const VoxelMegaState*,char*,size_t);
  Check check=(Check)dlsym(voxel_vk_library,"voxel_mega_checkpoint");
  if(!check) err_fail("checkpoint capability unavailable");
  VoxelVkFrame fresh_frame=*frame; fresh_frame.bodies=actual;
  char error[1024]; if(!check(&fresh_frame,&state,error,sizeof error)) err_fail(error);
  for(u32 i=0;i<frame->body_count;i++) { free((void*)raw[i].boxes); free((void*)actual[i].faces); free((void*)actual[i].vertices); }
  free(raw); free(actual);
  mega_stage("checkpoint",begin,voxel_vk_tick());
}
#else
static void voxel_mega_check(Env e,u64 st,u64 al,const VoxelVkFrame* frame) { (void)e; (void)st; (void)al; (void)frame; }
#endif

static VoxelVkFrame voxel_vk_scene(Env e, Term state, Term aim, const char* hud) {
  if (term_aux(state)!=CID_DEMO_STATE || term_aux(aim)!=CID_RENDER_AIM)
    err_fail("bad Vulkan scene state");
  // With Bend 2.0.32: State = World(7), Control(Camera(7) + 9), pending, last.
  if (cid_arity(CID_DEMO_STATE)!=25 || cid_arity(CID_WORLD_WORLD)!=7 ||
      cid_arity(CID_INPUT_CONTROL)!=16 || cid_arity(CID_RENDER_AIM)!=5 ||
      cid_arity(CID_WORLD_BODY)!=8 || cid_arity(CID_SPATIAL_FACE)!=8 ||
      cid_arity(CID_MESH_VERTEX)!=5 ||
      cid_arity(CID_SPATIAL_LEAF)!=7 || cid_arity(CID_SPATIAL_BRANCH)!=9)
    err_fail("Bend Vulkan state layout changed");
  u64 st=term_peek(e.mem,state),al=term_peek(e.mem,aim);
  VoxelVkFrame frame={0};
  for (u32 i=0;i<3;i++) {
    frame.eye[i]=voxel_vk_float(e.mem[st+7+i]);
    frame.aim[i]=voxel_vk_float(e.mem[al+i]);
  }
  frame.yaw=voxel_vk_float(e.mem[st+10]);
  frame.pitch=voxel_vk_float(e.mem[st+11]);
  frame.width=(u32)e.mem[st+12]; frame.height=(u32)e.mem[st+13];
  frame.night=((u32)e.mem[st+14]&256u)!=0; // Held L in Control.keys.
  frame.aim_kind=(u32)e.mem[al+4]; frame.hud=hud;
  memcpy(frame.colors,voxel_vk_colors,sizeof frame.colors);
  voxel_vk_generation++;
  u32 anchored=0,moving=0,translated=0;
  float minimum_offset=0;
  Term bodies=e.mem[st];
  while (term_aux(bodies)==CID_CON) {
    u64 link=term_peek(e.mem,bodies);
    Term body=e.mem[link];
    if (term_aux(body)!=CID_WORLD_BODY) err_fail("bad Vulkan body");
    u64 at=term_peek(e.mem,body);
    if (frame.body_count==voxel_vk_capacity) {
      voxel_vk_capacity=voxel_vk_capacity ? voxel_vk_capacity*2 : 256;
      voxel_vk_bodies=io_mem(realloc(voxel_vk_bodies,voxel_vk_capacity*sizeof *voxel_vk_bodies));
    }
    VoxelVkBody* out=&voxel_vk_bodies[frame.body_count++];
    out->id=(u32)e.mem[at]; out->revision=(u32)e.mem[at+1];
    out->offset=voxel_vk_float(e.mem[at+2]);
    // Bool fields are unboxed 0/1 in the pinned compiler.
    out->anchored=(u32)e.mem[at+4];
    anchored+=out->anchored;
    moving+=voxel_vk_float(e.mem[at+3])!=0;
    translated+=out->offset!=0;
    if (out->offset<minimum_offset) minimum_offset=out->offset;
    Term tree=e.mem[at+5];
    if (term_aux(tree)!=CID_SPATIAL_LEAF && term_aux(tree)!=CID_SPATIAL_BRANCH)
      err_fail("empty Vulkan body");
    u64 bounds=term_peek(e.mem,tree);
    for (u32 i=0;i<3;i++) {
      out->lo[i]=voxel_vk_float(e.mem[bounds+i]);
      out->hi[i]=voxel_vk_float(e.mem[bounds+3+i]);
    }
    VoxelVkTransport* entry=voxel_vk_transport(out->id,out->revision,e,e.mem[at+6],e.mem[at+7]);
    out->face_count=entry->count; out->faces=entry->faces;
    out->vertex_count=entry->vertex_count; out->vertices=entry->vertices;
    bodies=e.mem[link+1];
  }
  if (term_aux(bodies)!=CID_NIL) err_fail("bad Vulkan body list");
  for (u32 i=0;i<voxel_vk_cache_capacity;i++) {
    VoxelVkTransport* entry=&voxel_vk_cache[i];
    if (entry->valid && entry->seen!=voxel_vk_generation) {
      free(entry->faces); free(entry->vertices); memset(entry,0,sizeof *entry);
    }
  }
  if (getenv("VOXEL_STRESS"))
    fprintf(stdout,"bodies,%u,%u,%u,%u,%.6f\n",voxel_vk_generation-1,anchored,moving,translated,minimum_offset);
  if (mega_stream) {
    frame.full_geometry=1; frame.ground_half_extent=mega_ground; frame.record=mega_record;
    frame.evidence_frame=mega_frame; frame.gpu_evidence=1;
    if (anchored!=frame.body_count || moving || translated || frame.aim_kind || frame.night)
      err_fail("static Megascene state invariant failed");
    static u32 saved_state[14];
    u32 current_state[14];
    // Traversal may change only the camera; checkpoint comparison checks the
    // exact view bits while this guard protects world scalar state.
    for (u32 i=0;i<6;i++) current_state[i]=(u32)e.mem[st+1+i];
    for (u32 i=0;i<7;i++) current_state[6+i]=getenv("MEGASCENE_CAMERA_FILE")?0:(u32)e.mem[st+7+i];
    current_state[13]=frame.body_count;
    if (!mega_frame) memcpy(saved_state,current_state,sizeof saved_state);
    else if (memcmp(saved_state,current_state,sizeof saved_state)) err_fail("Megascene unchanged world state changed");
    for (u32 i=0;i<frame.body_count;i++)
      if (voxel_vk_bodies[i].id!=i+1 || voxel_vk_bodies[i].revision!=0)
        err_fail("static owner identity changed");
    char record[1024];
    snprintf(record,sizeof record,
      "\"record_type\":\"static_state\",\"anchored\":\"%u\",\"moving\":\"%u\",\"translated\":\"%u\",\"aim_kind\":\"%u\","
      "\"eye_m\":[\"0x%08x\",\"0x%08x\",\"0x%08x\"],\"yaw\":\"0x%08x\",\"pitch\":\"0x%08x\","
      "\"cells\":\"%u\",\"fragments\":\"%u\",\"removed\":\"%u\",\"next_id\":\"%u\",\"budget\":\"%u\"",
      anchored,moving,translated,frame.aim_kind,(u32)e.mem[st+7],(u32)e.mem[st+8],(u32)e.mem[st+9],
      (u32)e.mem[st+10],(u32)e.mem[st+11],(u32)e.mem[st+1],(u32)e.mem[st+2],(u32)e.mem[st+3],(u32)e.mem[st+5],(u32)e.mem[st+6]);
    mega_record(record);
  }
  frame.bodies=voxel_vk_bodies;
  if (mega_stream) voxel_mega_check(e,st,al,&frame);
  return frame;
}

static const u32 voxel_vk_keys[][2] = {
  {XK_Escape,27},{XK_Return,13},{XK_KP_Enter,13},{XK_Tab,9},
  {XK_BackSpace,127},{XK_Up,63232},{XK_Down,63233},{XK_Left,63234},
  {XK_Right,63235},{XK_Insert,63271},{XK_Delete,63272},{XK_Home,63273},
  {XK_End,63275},{XK_Page_Up,63276},{XK_Page_Down,63277},
  {XK_Shift_L,16},{XK_Shift_R,16},
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
  u64 at = heap_alloc(e, cls_fit(count));
  for (u32 i = 0; i < count; i += 1) e.mem[at + i] = ev[i + 1];
  return term_ctr(cid, at);
}
static Term voxel_vk_events(Env e, BendWin* win) {
  Term list = term_pak(CID_NIL, 0);
  for (u32 i = win->n; i > 0;) {
    i -= 1;
    u64 at = heap_alloc(e, 1);
    e.mem[at] = io_seal(e, voxel_vk_event(e, win->evs + 5 * i), CID_CON);
    e.mem[at + 1] = io_seal(e, list, CID_CON);
    list = term_ctr(CID_CON, at);
  }
  win->n = 0;
  return list;
}

Term vulkan_colors_run(Env e, Term* f, IoWork* work) {
  io_sync();
  if (voxel_vk_colors_ready) err_fail("Bend palette already initialized");
  voxel_vk_palette(e,f[1]);
  if (mega_stream) {
    BendWin* win=(BendWin*)(intptr_t)io_hand_v(f[0]);
    XSizeHints hints={0}; hints.flags=PMinSize|PMaxSize;
    hints.min_width=hints.max_width=win->img->width;
    hints.min_height=hints.max_height=win->img->height;
    XSetWMNormalHints(win->dpy,win->win,&hints);
    XSync(win->dpy,False);
  }
  return f[0];
}

Term vulkan_frame_run(Env e, Term* f, IoWork* work) {
  u64 mega_begin=mega_stream?voxel_vk_tick():0;
  int profile = getenv("VOXEL_STRESS") != NULL;
  u64 start = profile ? voxel_vk_tick() : 0;
  io_sync();
  if (!voxel_vk_colors_ready) err_fail("Bend palette was not initialized");
  voxel_vk_load();
  BendWin* win = (BendWin*)(intptr_t)io_hand_v(f[0]);
  u64 len = 0;
  char* hud = io_cstr(e, f[3], &len);
  VoxelVkFrame frame = voxel_vk_scene(e, f[1], f[2], hud);
  if (frame.width!=(u32)win->img->width || frame.height!=(u32)win->img->height)
    err_fail("Vulkan camera and window resolutions differ");
  static int stress_scene_logged;
  if (getenv("VOXEL_STRESS") && !stress_scene_logged++)
    {
    u32 faces=0;
    for (u32 i=0;i<frame.body_count;i++) faces+=frame.bodies[i].face_count;
    fprintf(stdout,"surface,%u\n",faces);
  }
  const char* view = getenv("VOXEL_STRESS_VIEW");
  if (view && strcmp(view,"0") != 0) {
    static u32 view_frame;
    fprintf(stdout,"view,%u,%.6f,%.6f,%.6f,%.6f,%.6f,%u,%.6f,%.6f,%.6f\n",
      view_frame++,frame.eye[0],frame.eye[1],frame.eye[2],frame.yaw,frame.pitch,
      frame.aim_kind,frame.aim[0],frame.aim[1],frame.aim[2]);
  }
  static u32 trace_frames;
  if (getenv("VOXEL_VULKAN_TRACE") && trace_frames++<10)
    fprintf(stderr,"vulkan frame eye %.3f %.3f %.3f yaw %.3f pitch %.3f bodies %u aim %u\n",
      frame.eye[0],frame.eye[1],frame.eye[2],frame.yaw,frame.pitch,frame.body_count,frame.aim_kind);
  char error[512] = {0};
  u64 prepared = profile ? voxel_vk_tick() : 0;
  VoxelVkTimings timings = {0};
  if (mega_stream) mega_stage("transport",mega_begin,voxel_vk_tick());
  u64 mega_render_begin=mega_stream?voxel_vk_tick():0;
  int ok = voxel_vk_render_fn(win->dpy, win->win, &frame, &timings, error, sizeof error);
  if (!ok) err_fail(error[0] ? error : "Vulkan frame failed");
  u64 rendered = profile ? voxel_vk_tick() : 0;
  if (mega_stream) mega_stage("renderer",mega_render_begin,voxel_vk_tick());
  u64 mega_events_begin=mega_stream?voxel_vk_tick():0;
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
  Term result=io_tup(e, f[0], io_tup(e, f[1], events));
  if (mega_stream) {
    mega_stage("events",mega_events_begin,voxel_vk_tick());
    // Last marker before handing control back to Bend. Recording this boundary
    // and subsequent bookkeeping belongs to the following frame interval.
    u64 end=voxel_vk_tick();
    char record[512];
    const char* population=!mega_frame?"startup":mega_frame<=mega_warmup?"warmup":"ordinary";
    char ordinal[32]="null";
    if (mega_frame>mega_warmup) snprintf(ordinal,sizeof ordinal,"\"%llu\"",(unsigned long long)(mega_frame-mega_warmup-1));
    snprintf(record,sizeof record,
      "\"record_type\":\"frame\",\"population\":\"%s\",\"begin_ns\":\"%llu\",\"end_ns\":\"%llu\",\"measured_ordinal\":%s,\"status\":\"measured\",\"unit\":\"ns\",\"scope\":\"frame_effect_returns\",\"duration_ns\":\"%llu\"",
      population,(unsigned long long)(mega_previous_end?mega_previous_end:mega_begin),
      (unsigned long long)end,ordinal,(unsigned long long)(end-(mega_previous_end?mega_previous_end:mega_begin)));
    // Frame identity zero is startup; subsequent identities index the frozen schedule.
    mega_reference(record);
    mega_record(record); mega_previous_end=end; mega_frame++;
  }
  return result;
}

Term vulkan_release_run(Env e, Term* f, IoWork* work) {
  if (voxel_vk_release_fn) voxel_vk_release_fn();
  if (voxel_vk_library) dlclose(voxel_vk_library);
  voxel_vk_library = NULL;
  voxel_vk_render_fn = NULL;
  voxel_vk_release_fn = NULL;
  for (u32 i=0;i<voxel_vk_cache_capacity;i++) {
    free(voxel_vk_cache[i].faces);
    free(voxel_vk_cache[i].vertices);
  }
  free(voxel_vk_cache); voxel_vk_cache=NULL; voxel_vk_cache_capacity=0;
  free(voxel_vk_bodies); voxel_vk_bodies=NULL;
  voxel_vk_capacity = 0;
  voxel_vk_colors_ready = 0;
  return f[0];
}

static void __attribute__((constructor)) voxel_vk_effects(void) {
  #ifdef CID_VULKAN_VULKAN_CAPTURE
  io_eff(CID_VULKAN_VULKAN_CAPTURE, vulkan_capture_run, 0);
  #endif
  io_eff(CID_VULKAN_VULKAN_COLORS, vulkan_colors_run, 0);
  io_eff(CID_VULKAN_VULKAN_FRAME, vulkan_frame_run, 0);
  io_eff(CID_VULKAN_VULKAN_RELEASE, vulkan_release_run, 0);
}
#endif
