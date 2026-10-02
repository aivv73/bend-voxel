function desktop_unavailable() {
  return { $: CID(Fail), error: io_tup(95, "UI: native X11 adapter unavailable") };
}

io_eff(CID(Desktop.key), desktop_unavailable);
io_eff(CID(Desktop.click), desktop_unavailable);
io_eff(CID(Desktop.close), desktop_unavailable);
io_eff(CID(Desktop.alive), desktop_unavailable);
