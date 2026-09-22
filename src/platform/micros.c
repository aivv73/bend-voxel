Term micros_run(Env e, Term* f, IoWork* w) {
  return (Term)(u32)(io_tick() / 1000ull);
}
static void __attribute__((constructor)) micros_use(void) {
  io_eff(CID_MICROS, micros_run, 0);
}
