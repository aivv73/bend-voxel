#define MEGA_REFERENCE_ONLY
#include "../src/vulkan/record.c"
#include <cerrno>
#include <cstdlib>
#include <limits>
#include <vector>

static bool number(const char* value, uint32_t& out) {
  if (*value < '0' || *value > '9') return false;
  char* end = nullptr;
  errno = 0;
  unsigned long long parsed = std::strtoull(value, &end, 10);
  if (errno || *end || parsed > std::numeric_limits<uint32_t>::max()) return false;
  out = static_cast<uint32_t>(parsed);
  return true;
}

int main(int argc, char** argv) {
  uint32_t count, warmup;
  if (argc != 4 || !number(argv[2], count) || !number(argv[3], warmup)) return 2;
  FILE* input = fopen(argv[1], "rb");
  if (!input) return 2;
  constexpr uint32_t guard = 0x8badf00d;
  std::vector<uint32_t> storage(21721 * 2 + 2, guard);
  uint32_t* rows = storage.data() + 1;
  bool valid = mega_schedule_policy_read(input, rows, count, warmup);
  int closed = fclose(input);
  if (storage.front() != guard || storage.back() != guard) return 3;
  if (!valid || closed) return 2;
  for (uint32_t at = 0; at < count; at++)
    printf("%u\t%u\n", rows[at * 2], rows[at * 2 + 1]);
  return 0;
}
