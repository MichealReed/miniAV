// Desktop Duplication damage chain, driven with made-up acquisitions: no D3D,
// no display. Each delivered frame's damage must describe exactly what changed
// since the frame delivered before it. Exit code 0 = pass.

#include "../windows/screen_dxgi_damage.h"

#include <stdio.h>
#include <string.h>

static int g_failures = 0;
#define CHECK(cond)                                                            \
  do {                                                                         \
    if (!(cond)) {                                                             \
      fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #cond);                  \
      ++g_failures;                                                            \
    }                                                                          \
  } while (0)

static DXGIDamageChain g_chain; // About 4 KB each: kept off the stack.
static DXGIFrameDamage g_frame;

static int has_rect(uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
  for (uint32_t i = 0; i < g_frame.rect_count; ++i) {
    const uint32_t *r = g_frame.rects[i];
    if (r[0] == x && r[1] == y && r[2] == w && r[3] == h)
      return 1;
  }
  return 0;
}

static void deliver(int certifiable) {
  memset(&g_frame, 0xCD, sizeof g_frame);
  dxgi_damage_deliver(&g_chain, certifiable, &g_frame);
}

int main(void) {
  dxgi_damage_chain_start(&g_chain, 7, 1920, 1080);

  // The first frame of a chain is whole, whatever was collected before it.
  dxgi_damage_add_rect(&g_chain, 0, 0, 10, 10);
  deliver(1);
  CHECK(g_frame.certified && g_frame.source_epoch == 7);
  CHECK(g_frame.generation == 1 && g_frame.full_frame && !g_frame.rect_count);
  CHECK(g_frame.width == 1920 && g_frame.height == 1080);

  // Pointer-only acquisitions add nothing and use up no generation, so the
  // next delivered frame is still consecutive and partial.
  dxgi_damage_add_rect(&g_chain, 100, 200, 30, 40);
  deliver(1);
  CHECK(g_frame.certified && g_frame.generation == 2 && !g_frame.full_frame);
  CHECK(g_frame.rect_count == 1 && has_rect(100, 200, 30, 40));

  // An acquisition that is never delivered (its copy failed) hands its
  // changes to the next delivered frame.
  dxgi_damage_add_rect(&g_chain, 0, 0, 16, 16);   // Not delivered.
  dxgi_damage_add_rect(&g_chain, 500, 500, 8, 8); // Delivered.
  deliver(1);
  CHECK(g_frame.generation == 3 && !g_frame.full_frame);
  CHECK(g_frame.rect_count == 2 && has_rect(0, 0, 16, 16) &&
        has_rect(500, 500, 8, 8));

  // A rectangle already covered is not repeated; touching edges are kept.
  dxgi_damage_add_rect(&g_chain, 10, 10, 50, 50);
  dxgi_damage_add_rect(&g_chain, 20, 20, 5, 5);
  dxgi_damage_add_rect(&g_chain, 10, 10, 50, 50);
  dxgi_damage_add_rect(&g_chain, 60, 10, 1, 1);
  deliver(1);
  CHECK(g_frame.generation == 4 && g_frame.rect_count == 2);
  CHECK(has_rect(10, 10, 50, 50) && has_rect(60, 10, 1, 1));

  // The last pixel is inside; one past it, or an empty or negative
  // rectangle, makes the frame whole. The chain carries on afterwards.
  dxgi_damage_add_rect(&g_chain, 1919, 1079, 1, 1);
  deliver(1);
  CHECK(g_frame.generation == 5 && !g_frame.full_frame &&
        has_rect(1919, 1079, 1, 1));
  const int64_t bad[][4] = {{1900, 0, 21, 1}, {0, 1079, 1, 2}, {-1, 0, 1, 1},
                            {0, -1, 1, 1},    {0, 0, 0, 1},    {0, 0, 1, -3}};
  for (size_t i = 0; i < sizeof bad / sizeof bad[0]; ++i) {
    dxgi_damage_add_rect(&g_chain, 4, 4, 2, 2);
    dxgi_damage_add_rect(&g_chain, bad[i][0], bad[i][1], bad[i][2], bad[i][3]);
    dxgi_damage_add_rect(&g_chain, 8, 8, 2, 2);
    deliver(1);
    CHECK(g_frame.certified && g_frame.full_frame && !g_frame.rect_count);
  }
  dxgi_damage_add_rect(&g_chain, 4, 4, 2, 2);
  deliver(1);
  CHECK(g_frame.generation == 12 && !g_frame.full_frame &&
        g_frame.rect_count == 1);

  // 256 distinct rectangles fit; the 257th makes the frame whole.
  for (uint32_t i = 0; i < DXGI_DAMAGE_MAX_RECTS; ++i)
    dxgi_damage_add_rect(&g_chain, i * 4, 0, 2, 2);
  deliver(1);
  CHECK(!g_frame.full_frame && g_frame.rect_count == DXGI_DAMAGE_MAX_RECTS);
  for (uint32_t i = 0; i <= DXGI_DAMAGE_MAX_RECTS; ++i)
    dxgi_damage_add_rect(&g_chain, i * 4, 0, 2, 2);
  deliver(1);
  CHECK(g_frame.full_frame && !g_frame.rect_count);

  // A frame that is not a finished snapshot (or not in the chain's format)
  // is not certified, and the frame after it is whole.
  dxgi_damage_add_rect(&g_chain, 30, 30, 4, 4);
  deliver(0);
  CHECK(!g_frame.certified && g_frame.generation == 15);
  dxgi_damage_add_rect(&g_chain, 40, 40, 4, 4);
  deliver(1);
  CHECK(g_frame.certified && g_frame.generation == 16 && g_frame.full_frame);
  dxgi_damage_add_rect(&g_chain, 40, 40, 4, 4);
  deliver(1);
  CHECK(g_frame.certified && !g_frame.full_frame && g_frame.rect_count == 1);

  // A whole-frame change wipes rectangles collected before it.
  dxgi_damage_add_rect(&g_chain, 1, 1, 1, 1);
  dxgi_damage_mark_full(&g_chain);
  dxgi_damage_add_rect(&g_chain, 2, 2, 1, 1);
  deliver(1);
  CHECK(g_frame.full_frame && !g_frame.rect_count);

  // An empty changed set is never reported.
  deliver(1);
  CHECK(g_frame.certified && g_frame.full_frame && !g_frame.rect_count);

  // A new chain (capture restarted, duplication recreated) starts again at
  // generation 1 of its epoch, whole.
  dxgi_damage_chain_start(&g_chain, 8, 1280, 720);
  dxgi_damage_add_rect(&g_chain, 0, 0, 1, 1);
  deliver(1);
  CHECK(g_frame.source_epoch == 8 && g_frame.generation == 1);
  CHECK(g_frame.full_frame && g_frame.width == 1280 && g_frame.height == 720);

  // A chain that was never started certifies nothing.
  memset(&g_chain, 0, sizeof g_chain);
  deliver(1);
  CHECK(!g_frame.certified);

  if (g_failures) {
    printf("test_dxgi_damage: %d check(s) FAILED\n", g_failures);
    return 1;
  }
  printf("test_dxgi_damage: ok\n");
  return 0;
}
