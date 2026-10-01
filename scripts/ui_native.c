#if defined(__linux__) && !defined(__OBJC__)
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>

typedef struct {
  Display* display;
  Window id;
  XWindowAttributes attrs;
  int (*previous_error)(Display*, XErrorEvent*);
} UiConnection;

static int ui_x11_error;

static int ui_x11_bad_window(Display* display, XErrorEvent* error) {
  ui_x11_error = error->error_code;
  return 0;
}

static bool ui_x11_open(Env e, Term* args, UiConnection* connection) {
  u64 length = 0;
  char* name = io_cstr(e, args[0], &length);
  connection->display = XOpenDisplay(name);
  free(name);
  if (connection->display == NULL) {
    return false;
  }
  connection->id = (u32)args[1];
  ui_x11_error = 0;
  connection->previous_error = XSetErrorHandler(ui_x11_bad_window);
  if (!XGetWindowAttributes(connection->display, connection->id, &connection->attrs)) {
    ui_x11_error = BadWindow;
  }
  XSync(connection->display, False);
  return true;
}

static void ui_x11_finish(UiConnection* connection) {
  XCloseDisplay(connection->display);
  XSetErrorHandler(connection->previous_error);
}

#ifdef CID(Desktop.capture)
static u32 ui_x11_channel(unsigned long pixel, unsigned long mask) {
  if (mask == 0) {
    return 0;
  }
  while ((mask & 1) == 0) {
    mask >>= 1;
    pixel >>= 1;
  }
  return (u32)(((u64)(pixel & mask) * 255) / mask);
}

static Term ui_x11_node(Env e, u64 cid, const Term* fields) {
  u32 count = cid_arity(cid);
  u64 at = heap_alloc(e, cls_fit(count));
  for (u32 i = 0; i < count; i += 1) {
    e.mem[at + i] = io_seal(e, fields[i], cid);
  }
  return term_ctr(cid, at);
}

static Term ui_x11_image(Env e, XImage* image, unsigned int x,
  unsigned int y, unsigned int size) {
  if (size == 1) {
    unsigned long pixel = XGetPixel(image, x, y);
    u32 color = (ui_x11_channel(pixel, image->red_mask) << 16)
      | (ui_x11_channel(pixel, image->green_mask) << 8)
      | ui_x11_channel(pixel, image->blue_mask);
    return term_pak(CID(Pix), color);
  }
  unsigned int half = size / 2;
  Term tl = ui_x11_image(e, image, x, y, half);
  Term tr = ui_x11_image(e, image, x + half, y, half);
  Term bl = ui_x11_image(e, image, x, y + half, half);
  Term br = ui_x11_image(e, image, x + half, y + half, half);
  Term fields[] = {tl, tr, bl, br};
  return ui_x11_node(e, CID(Qua), fields);
}
#endif
#endif

#ifdef CID(Desktop.capture)
Term desktop_capture_run(Env e, Term* args, IoWork* work) {
#if defined(__linux__) && !defined(__OBJC__)
  UiConnection connection;
  if (!ui_x11_open(e, args, &connection)) {
    return io_fail(e, EIO, "UI capture: cannot open exported display");
  }
  if (ui_x11_error != 0 || connection.attrs.map_state != IsViewable
    || connection.attrs.width != 512 || connection.attrs.height != 512
    || connection.attrs.visual->class != TrueColor) {
    ui_x11_finish(&connection);
    return io_fail(e, EIO, "UI capture: expected a visible 512x512 TrueColor window");
  }
  XImage* image = XGetImage(connection.display, connection.id, 0, 0,
    512, 512, AllPlanes, ZPixmap);
  XSync(connection.display, False);
  if (image == NULL || ui_x11_error != 0) {
    if (image != NULL) {
      XDestroyImage(image);
    }
    ui_x11_finish(&connection);
    return io_fail(e, EIO, "UI capture: cannot read exported window pixels");
  }
  Term result = ui_x11_image(e, image, 0, 0, 512);
  XDestroyImage(image);
  ui_x11_finish(&connection);
  return io_done(e, result);
#else
  return io_fail(e, ENOTSUP, "UI capture: X11 adapter unavailable");
#endif
}
#endif

#ifdef CID(Desktop.key)
Term desktop_key_run(Env e, Term* args, IoWork* work) {
#if defined(__linux__) && !defined(__OBJC__)
  UiConnection connection;
  if (!ui_x11_open(e, args, &connection)) {
    return io_fail(e, EIO, "UI key: cannot open exported display");
  }
  if (ui_x11_error != 0) {
    ui_x11_finish(&connection);
    return io_fail(e, EIO, "UI key: exported window has expired");
  }
  KeySym symbol = (u32)args[2] == 27 ? XK_Escape : (KeySym)(u32)args[2];
  KeyCode code = XKeysymToKeycode(connection.display, symbol);
  XEvent event = {0};
  event.xkey.display = connection.display;
  event.xkey.window = connection.id;
  event.xkey.root = connection.attrs.root;
  event.xkey.time = CurrentTime;
  event.xkey.same_screen = True;
  event.xkey.keycode = code;
  event.xkey.type = KeyPress;
  bool ok = code != 0 && XSendEvent(connection.display, connection.id,
    False, KeyPressMask, &event) != 0;
  event.xkey.type = KeyRelease;
  ok = ok && XSendEvent(connection.display, connection.id,
    False, KeyReleaseMask, &event) != 0;
  XSync(connection.display, False);
  ok = ok && ui_x11_error == 0;
  ui_x11_finish(&connection);
  return ok ? io_done(e, term_pak(CID(Unit), 0))
    : io_fail(e, EIO, "UI key: native event delivery failed");
#else
  return io_fail(e, ENOTSUP, "UI key: X11 adapter unavailable");
#endif
}
#endif

#ifdef CID(Desktop.click)
Term desktop_click_run(Env e, Term* args, IoWork* work) {
#if defined(__linux__) && !defined(__OBJC__)
  UiConnection connection;
  if (!ui_x11_open(e, args, &connection)) {
    return io_fail(e, EIO, "UI click: cannot open exported display");
  }
  if (ui_x11_error != 0) {
    ui_x11_finish(&connection);
    return io_fail(e, EIO, "UI click: exported window has expired");
  }
  XEvent event = {0};
  event.xbutton.display = connection.display;
  event.xbutton.window = connection.id;
  event.xbutton.root = connection.attrs.root;
  event.xbutton.time = CurrentTime;
  event.xbutton.same_screen = True;
  event.xbutton.x = (u32)args[2];
  event.xbutton.y = (u32)args[3];
  event.xbutton.button = Button1;
  event.xbutton.type = ButtonPress;
  bool ok = XSendEvent(connection.display, connection.id,
    False, ButtonPressMask, &event) != 0;
  event.xbutton.type = ButtonRelease;
  ok = ok && XSendEvent(connection.display, connection.id,
    False, ButtonReleaseMask, &event) != 0;
  XSync(connection.display, False);
  ok = ok && ui_x11_error == 0;
  ui_x11_finish(&connection);
  return ok ? io_done(e, term_pak(CID(Unit), 0))
    : io_fail(e, EIO, "UI click: native event delivery failed");
#else
  return io_fail(e, ENOTSUP, "UI click: X11 adapter unavailable");
#endif
}
#endif

#ifdef CID(Desktop.close)
Term desktop_close_run(Env e, Term* args, IoWork* work) {
#if defined(__linux__) && !defined(__OBJC__)
  UiConnection connection;
  if (!ui_x11_open(e, args, &connection)) {
    return io_fail(e, EIO, "UI close: cannot open exported display");
  }
  if (ui_x11_error != 0) {
    ui_x11_finish(&connection);
    return io_fail(e, EIO, "UI close: exported window has expired");
  }
  XEvent event = {0};
  event.xclient.type = ClientMessage;
  event.xclient.display = connection.display;
  event.xclient.window = connection.id;
  event.xclient.message_type = XInternAtom(connection.display, "WM_PROTOCOLS", False);
  event.xclient.format = 32;
  event.xclient.data.l[0] = XInternAtom(connection.display, "WM_DELETE_WINDOW", False);
  bool ok = XSendEvent(connection.display, connection.id, False,
    NoEventMask, &event) != 0;
  XSync(connection.display, False);
  ok = ok && ui_x11_error == 0;
  ui_x11_finish(&connection);
  return ok ? io_done(e, term_pak(CID(Unit), 0))
    : io_fail(e, EIO, "UI close: native event delivery failed");
#else
  return io_fail(e, ENOTSUP, "UI close: X11 adapter unavailable");
#endif
}
#endif

#ifdef CID(Desktop.alive)
Term desktop_alive_run(Env e, Term* args, IoWork* work) {
#if defined(__linux__) && !defined(__OBJC__)
  UiConnection connection;
  if (!ui_x11_open(e, args, &connection)) {
    return io_fail(e, EIO, "UI alive: cannot open exported display");
  }
  bool alive = ui_x11_error == 0;
  ui_x11_finish(&connection);
  return io_done(e, term_pak(alive ? CID(True) : CID(False), 0));
#else
  return io_fail(e, ENOTSUP, "UI alive: X11 adapter unavailable");
#endif
}
#endif

static void __attribute__((constructor)) ui_native_use(void) {
#ifdef CID(Desktop.capture)
  io_eff(CID(Desktop.capture), desktop_capture_run, 0);
#endif
#ifdef CID(Desktop.key)
  io_eff(CID(Desktop.key), desktop_key_run, 0);
#endif
#ifdef CID(Desktop.click)
  io_eff(CID(Desktop.click), desktop_click_run, 0);
#endif
#ifdef CID(Desktop.close)
  io_eff(CID(Desktop.close), desktop_close_run, 0);
#endif
#ifdef CID(Desktop.alive)
  io_eff(CID(Desktop.alive), desktop_alive_run, 0);
#endif
}
