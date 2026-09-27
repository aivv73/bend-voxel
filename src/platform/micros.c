Term micros_run(Env e, Term* f, IoWork* w) {
  return (Term)(u32)(io_tick() / 1000ull);
}
static void __attribute__((constructor)) micros_use(void) {
#if defined(CID_PLATFORM_MICROS)
  io_eff(CID_PLATFORM_MICROS, micros_run, 0);
#elif defined(CID____SRC_PLATFORM_MICROS)
  // The test entrypoint lives under tests/ and imports ../src/platform.bend.
  io_eff(CID____SRC_PLATFORM_MICROS, micros_run, 0);
#else
#error Unknown Bend platform.micros effect ID
#endif
}
