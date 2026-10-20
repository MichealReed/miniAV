#pragma once
// Private single-use storage for the ACTUAL C++/WinRT delegate type. The type
// inherits its handler's class new/delete; no custom COM implementation is used.
#include <array>
#include <atomic>
#include <cstddef>
#include <cstring>
#include <memory>
#include <new>
#include <utility>

namespace miniav::wgc_delegate_storage {
enum class Phase { fresh, allocating, owned, releasing, freed, quarantined };
struct Header {
  std::atomic<Phase> phase{Phase::fresh};
  std::shared_ptr<void> keeper;
  void *body = nullptr;
  const void *kind = nullptr;
  size_t bytes = 0, alignment = 0;
  void (*unknown)(void *) noexcept = nullptr;
};
template<class T> inline unsigned char kind_key{};
template<class T> struct Slot {
  static constexpr size_t prefix =
      ((sizeof(Header *) + alignof(T) - 1) / alignof(T)) * alignof(T);
  Header header;
  alignas(T) std::array<std::byte, prefix + sizeof(T)> storage{};
  void *address() noexcept { return storage.data() + prefix; }
};
struct Cursor {
  Header *header;
  void *body;
  const void *kind;
  size_t bytes, alignment;
  const std::shared_ptr<void> &keeper;
  void (*unknown)(void *) noexcept;
  bool consumed = false;
};
// No heap-backed registry. This pointer's per-thread/platform cost is separate
// from the requested Owner bytes, and must be included in worker qualification.
inline thread_local Cursor *current = nullptr;

template<class T> class Scope {
public:
  Scope(Slot<T> &slot, std::shared_ptr<void> keeper,
      void (*unknown)(void *) noexcept)
      : keeper_(std::move(keeper)), previous_(current),
        cursor_{&slot.header, slot.address(), &kind_key<T>, sizeof(T), alignof(T),
                keeper_, unknown} { current = &cursor_; }
  Scope(const Scope &) = delete;
  Scope &operator=(const Scope &) = delete;
  ~Scope() { current = previous_; }
private:
  std::shared_ptr<void> keeper_;
  Cursor *previous_;
  Cursor cursor_;
};

template<class T> void *allocate(size_t bytes) {
  auto *cursor = current;
  if (!cursor || cursor->consumed || cursor->kind != &kind_key<T> ||
      bytes != sizeof(T) || cursor->bytes != sizeof(T) ||
      cursor->alignment != alignof(T) || !cursor->keeper)
    throw std::bad_alloc();
  auto &header = *cursor->header;
  auto expected = Phase::fresh;
  if (!header.phase.compare_exchange_strong(expected, Phase::allocating))
    throw std::bad_alloc();
  header.keeper = cursor->keeper;
  header.body = cursor->body;
  header.kind = cursor->kind;
  header.bytes = bytes;
  header.alignment = alignof(T);
  header.unknown = cursor->unknown;
  auto *address = static_cast<std::byte *>(cursor->body);
  auto *identity = &header;
  std::memcpy(address - sizeof(identity), &identity, sizeof(identity));
  cursor->consumed = true;
  header.phase.store(Phase::owned, std::memory_order_release);
  return address;
}

template<class T> void release(void *address) noexcept {
  if (!address) return;
  // Only the matching class delete receives this exact pointer. As with COM
  // itself, stale/arbitrary native pointers are not a supported calling contract.
  Header *header = nullptr;
  std::memcpy(&header, static_cast<std::byte *>(address) - sizeof(header), sizeof(header));
  if (!header) return;
  auto expected = Phase::owned;
  if (!header->phase.compare_exchange_strong(expected, Phase::releasing)) return;
  if (header->body != address || header->kind != &kind_key<T> ||
      header->bytes != sizeof(T) || header->alignment != alignof(T) || !header->keeper) {
    header->phase.store(Phase::quarantined, std::memory_order_release);
    if (header->unknown && header->keeper) header->unknown(header->keeper.get());
    return; // Preserve the original self-retention/debt on uncertainty.
  }
  // The handler/ticket destructor has already run. An independent keeper is
  // required until THIS epilogue has finished touching storage inside the Owner.
  auto retained = std::move(header->keeper);
  header->phase.store(Phase::freed, std::memory_order_release);
  // No header/address access after retained is released. Slots never recycle.
}
}
