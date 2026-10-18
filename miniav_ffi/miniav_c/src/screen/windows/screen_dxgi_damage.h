#ifndef MINIAV_SCREEN_DXGI_DAMAGE_H
#define MINIAV_SCREEN_DXGI_DAMAGE_H

// Desktop Duplication damage bookkeeping, kept free of D3D so
// test_dxgi_damage can drive it with made-up acquisitions.
//
// A chain numbers the frames it DELIVERS (1, 2, 3, ...) within one source
// epoch. Every acquisition adds its changes to the pending set, delivered or
// not (pointer-only updates, failed copies), so a delivered frame's damage is
// relative to the frame delivered just before it.

#include <stdint.h>

// Keep metadata bounded and private; public buffer/plane layouts are unchanged.
#define DXGI_DAMAGE_MAX_RECTS 256

typedef struct DXGIFrameDamage {
  uint64_t source_epoch;
  uint64_t generation;
  uint32_t width;
  uint32_t height;
  uint32_t full_frame;
  uint32_t rect_count;
  uint32_t rects[DXGI_DAMAGE_MAX_RECTS][4]; // x, y, width, height
  uint32_t certified;
} DXGIFrameDamage;

typedef struct DXGIDamageChain {
  uint64_t source_epoch;
  uint64_t generation;     // Of the last delivered frame; 0 before the first.
  DXGIFrameDamage pending; // Changes since then: size, full_frame and rects.
} DXGIDamageChain;

// Starts a new chain: the next delivered frame is generation 1 of `epoch` and
// reports the whole frame.
static inline void dxgi_damage_chain_start(DXGIDamageChain *chain,
                                           uint64_t epoch, uint32_t width,
                                           uint32_t height) {
  chain->source_epoch = epoch;
  chain->generation = 0;
  chain->pending.width = width;
  chain->pending.height = height;
  chain->pending.full_frame = 1;
  chain->pending.rect_count = 0;
}

// Something changed that the rectangles cannot describe.
static inline void dxgi_damage_mark_full(DXGIDamageChain *chain) {
  chain->pending.full_frame = 1;
  chain->pending.rect_count = 0;
}

// Adds one changed rectangle. Malformed or out-of-bounds metadata, and more
// rectangles than fit, must never authorize partial work: the whole frame
// counts as changed instead.
static inline void dxgi_damage_add_rect(DXGIDamageChain *chain, int64_t x,
                                        int64_t y, int64_t width,
                                        int64_t height) {
  DXGIFrameDamage *pending = &chain->pending;
  if (pending->full_frame)
    return;
  if (x < 0 || y < 0 || width <= 0 || height <= 0 ||
      x + width > (int64_t)pending->width ||
      y + height > (int64_t)pending->height) {
    dxgi_damage_mark_full(chain);
    return;
  }
  // A rectangle already covered adds nothing (a caret blinking across
  // undelivered acquisitions repeats the same one).
  for (uint32_t i = 0; i < pending->rect_count; ++i) {
    const uint32_t *r = pending->rects[i];
    if (x >= (int64_t)r[0] && y >= (int64_t)r[1] &&
        x + width <= (int64_t)r[0] + r[2] && y + height <= (int64_t)r[1] + r[3])
      return;
  }
  if (pending->rect_count >= DXGI_DAMAGE_MAX_RECTS) {
    dxgi_damage_mark_full(chain);
    return;
  }
  uint32_t *rect = pending->rects[pending->rect_count++];
  rect[0] = (uint32_t)x;
  rect[1] = (uint32_t)y;
  rect[2] = (uint32_t)width;
  rect[3] = (uint32_t)height;
}

// Hands the changes since the last delivered frame to the frame delivered now
// and starts collecting for the next one. `certifiable` says the frame is a
// finished private snapshot at the chain's own size and format. A frame that
// is not cannot be built on, so the frame after it reports the whole frame.
static inline void dxgi_damage_deliver(DXGIDamageChain *chain, int certifiable,
                                       DXGIFrameDamage *out) {
  DXGIFrameDamage *pending = &chain->pending;
  if (!pending->rect_count) // An empty changed set is never reported.
    pending->full_frame = 1;
  out->source_epoch = chain->source_epoch;
  out->generation = ++chain->generation;
  out->width = pending->width;
  out->height = pending->height;
  out->full_frame = pending->full_frame;
  out->rect_count = pending->full_frame ? 0 : pending->rect_count;
  for (uint32_t i = 0; i < out->rect_count; ++i)
    for (uint32_t j = 0; j < 4; ++j)
      out->rects[i][j] = pending->rects[i][j];
  out->certified = certifiable && chain->source_epoch != 0;
  pending->full_frame = !out->certified;
  pending->rect_count = 0;
}

#endif // MINIAV_SCREEN_DXGI_DAMAGE_H
