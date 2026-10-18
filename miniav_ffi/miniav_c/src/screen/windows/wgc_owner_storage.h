#pragma once
// Private requested-allocation custody. The trusted host reserves all roles in
// its ORIGINAL budget before entry and pins callback code through every copy.
// A profile/key is neither source permission nor a replacement budget.
// Callbacks are ledger-only: no allocation, foreign calls, source reentry or
// exceptions. They do not infer worker join from storage disposition.
#include <cstddef>
#include <cstdint>
#include <limits>
#include <memory>
#include <new>
#include <type_traits>
#include <utility>
#include "../../../include/miniav_screen_windows_strict.h"

#if defined(_WIN32) && defined(_M_X64) && !defined(__clang__) && \
    defined(_MSC_VER) && _MSC_VER == 1940 && _MSC_FULL_VER == 194033818 && \
    _MSVC_STL_VERSION == 143 && _MSVC_STL_UPDATE == 202402L && \
    defined(NDEBUG) && !defined(_DEBUG) && _ITERATOR_DEBUG_LEVEL == 0 && \
    defined(_MT) && defined(_DLL) && _MSVC_LANG == 201703L && \
    !defined(MINIAV_OWNER_STORAGE_FORCE_UNSUPPORTED)
#define MINIAV_KNOWN_OWNER_STORAGE 1
#else
#define MINIAV_KNOWN_OWNER_STORAGE 0
#endif

namespace miniav::wgc_owner_storage {
struct Extent {
  uint64_t bytes = 0;
  uint32_t alignment = 0;
};
struct Key {
  uint64_t generation = 0, source_epoch = 0;
  uint32_t row = 0, role = 0;
};
enum class Event : uint32_t {
  BeginAllocation, Allocated, Constructed, Disposed, BeginDeallocation,
  FreeReturned, AllocationFailed, CancelUnallocated, Quarantine, ColdScopeClosed
};
using EventRecord = MiniAVWindowsStrictControlStorageEventV1;
using Ops = MiniAVWindowsStrictControlStorageOpsV1;
static_assert(sizeof(EventRecord) == 56 && offsetof(EventRecord, address) == 40);
enum class Error { Refused, Uncertain };

inline constexpr bool layout_supported = MINIAV_KNOWN_OWNER_STORAGE != 0;

inline void identity(uint32_t (&out)[10]) noexcept {
  for (auto &value : out) value = 0;
  out[0] = 1;
#ifdef _MSC_FULL_VER
  out[1] = _MSC_FULL_VER;
#endif
#ifdef _MSVC_STL_VERSION
  out[2] = _MSVC_STL_VERSION;
  out[3] = _MSVC_STL_UPDATE;
  out[4] = _ITERATOR_DEBUG_LEVEL;
#endif
#ifdef _MSVC_LANG
  out[5] = _MSVC_LANG;
#else
  out[5] = __cplusplus;
#endif
#ifdef NDEBUG
  out[6] |= 1;
#endif
#ifdef _DEBUG
  out[6] |= 2;
#endif
#ifdef _MT
  out[6] |= 4;
#endif
#ifdef _DLL
  out[6] |= 8;
#endif
#ifdef _WIN32
  out[6] |= 16;
#endif
#ifdef _M_X64
  out[6] |= 32;
#endif
  out[7] = sizeof(void *);
  out[8] = __STDCPP_DEFAULT_NEW_ALIGNMENT__;
}

class Ticket {
public:
  Ticket() noexcept = default;
  static Ticket retain(void *context, const Ops *ops, Key key, Extent extent) noexcept {
    Ticket result;
    if (!context || !ops || !ops->retain || !ops->release || !ops->event ||
        !key.generation || !key.source_epoch || key.role >= 4 || !extent.bytes ||
        extent.bytes > static_cast<uint64_t>((std::numeric_limits<ptrdiff_t>::max)()) ||
        !extent.alignment || (extent.alignment & (extent.alignment - 1)) ||
        extent.bytes % extent.alignment) return result;
    result.context_ = context; result.ops_ = ops;
    result.key_ = key; result.extent_ = extent;
    ops->retain(context);
    return result;
  }
  Ticket(const Ticket &other) noexcept
      : context_(other.context_), ops_(other.ops_), key_(other.key_), extent_(other.extent_) {
    if (context_) ops_->retain(context_);
  }
  Ticket(Ticket &&other) noexcept
      : context_(std::exchange(other.context_, nullptr)), ops_(other.ops_),
        key_(other.key_), extent_(other.extent_) {}
  Ticket &operator=(Ticket other) noexcept { swap(other); return *this; }
  ~Ticket() { if (context_) ops_->release(context_); }
  void swap(Ticket &other) noexcept {
    std::swap(context_, other.context_); std::swap(ops_, other.ops_);
    std::swap(key_, other.key_); std::swap(extent_, other.extent_);
  }
  explicit operator bool() const noexcept { return context_ != nullptr; }
  bool role(uint32_t expected) const noexcept { return context_ && key_.role == expected; }
  bool same_transaction(const Ticket &other) const noexcept {
    return context_ && context_ == other.context_ && ops_ == other.ops_ &&
        key_.generation == other.key_.generation && key_.source_epoch == other.key_.source_epoch &&
        key_.row == other.key_.row;
  }
  bool same(const Ticket &other) const noexcept {
    return same_transaction(other) && key_.role == other.key_.role &&
        extent_.bytes == other.extent_.bytes && extent_.alignment == other.extent_.alignment;
  }
  bool matches(Extent extent) const noexcept {
    return context_ && extent.bytes == extent_.bytes && extent.alignment == extent_.alignment;
  }
  bool notify(Event event, uintptr_t address = 0) const noexcept {
    if (!context_) return false;
    const EventRecord record{sizeof(EventRecord), 1, static_cast<uint32_t>(event),
        key_.role, key_.generation, key_.source_epoch, key_.row, extent_.alignment,
        static_cast<uint64_t>(address), extent_.bytes};
    return ops_->event(context_, &record) == 1;
  }
  void quarantine() const noexcept {
    if (!context_) return;
    // Independent original-authority retention survives even a refused event.
    // No allocation, new budget or payload is needed to retain this uncertainty.
    ops_->retain(context_);
    (void)notify(Event::Quarantine);
  }
  void *allocate(size_t bytes, size_t alignment) const {
    if (!matches({bytes, static_cast<uint32_t>(alignment)}) ||
        !notify(Event::BeginAllocation)) throw Error::Refused;
    void *value;
    try {
      value = alignment > __STDCPP_DEFAULT_NEW_ALIGNMENT__ ?
          ::operator new(bytes, std::align_val_t(alignment)) : ::operator new(bytes);
    } catch (...) {
      if (!notify(Event::AllocationFailed)) quarantine();
      throw;
    }
    if (!notify(Event::Allocated, reinterpret_cast<uintptr_t>(value))) {
      quarantine(); // Unknown address receipt: never free or publish the block.
      throw Error::Uncertain;
    }
    return value;
  }
  bool begin_free(void *value, size_t bytes, size_t alignment) const noexcept {
    if (value && matches({bytes, static_cast<uint32_t>(alignment)}) &&
        notify(Event::BeginDeallocation, reinterpret_cast<uintptr_t>(value))) return true;
    quarantine();
    return false;
  }
  void free_returned(void *value, size_t alignment) const noexcept {
    const auto address = reinterpret_cast<uintptr_t>(value);
    if (alignment > __STDCPP_DEFAULT_NEW_ALIGNMENT__) ::operator delete(value, std::align_val_t(alignment));
    else ::operator delete(value);
    if (!notify(Event::FreeReturned, address)) quarantine();
  }
private:
  void *context_ = nullptr;
  const Ops *ops_ = nullptr;
  Key key_{};
  Extent extent_{};
};

class Pending {
public:
  explicit Pending(Ticket value) noexcept : ticket_(std::move(value)) {}
  ~Pending() { (void)ticket_.notify(Event::CancelUnallocated); }
  Pending(const Pending &) = delete;
private:
  Ticket ticket_;
};

template<class T> class Allocator {
public:
  using value_type = T;
  explicit Allocator(Ticket ticket) noexcept : ticket_(std::move(ticket)) {}
  template<class U> Allocator(const Allocator<U> &other) noexcept : ticket_(other.ticket_) {}
  T *allocate(size_t count) {
    if (count != 1) throw Error::Refused;
    return static_cast<T *>(ticket_.allocate(sizeof(T), alignof(T)));
  }
  void deallocate(T *value, size_t count) noexcept {
    if (ticket_.begin_free(value, count == 1 ? sizeof(T) : 0, alignof(T)))
      ticket_.free_returned(value, alignof(T));
  }
  template<class U, class... Args> void construct(U *value, Args &&...args) {
    static_assert(std::is_nothrow_destructible_v<U>);
    ::new (static_cast<void *>(value)) U(std::forward<Args>(args)...);
    if (!ticket_.notify(Event::Constructed)) {
      ticket_.quarantine();
      value->~U(); // STL assumes construction failed when the receipt throws.
      throw Error::Uncertain;
    }
  }
  template<class U> void destroy(U *value) noexcept {
    static_assert(std::is_nothrow_destructible_v<U>);
    value->~U();
    if (!ticket_.notify(Event::Disposed)) ticket_.quarantine();
  }
  template<class U> bool operator==(const Allocator<U> &other) const noexcept { return ticket_.same(other.ticket_); }
  template<class U> bool operator!=(const Allocator<U> &other) const noexcept { return !(*this == other); }
private:
  template<class> friend class Allocator;
  Ticket ticket_;
};

template<class T> constexpr Extent shared_extent() noexcept {
#if MINIAV_KNOWN_OWNER_STORAGE
  // Inspected MSVC memory: allocate_shared non-array selects this exact type
  // under both C++17 and20; this adapter intentionally qualifies C++17 only.
  using Block = std::_Ref_count_obj_alloc3<std::remove_cv_t<T>, Allocator<T>>;
  return {sizeof(Block), alignof(Block)};
#else
  return {}; // No guessed control-block header, surrogate or runtime allocation.
#endif
}
template<class T, class... Args> std::shared_ptr<T> make_shared(Ticket ticket, Args &&...args) {
  const auto extent = shared_extent<T>();
  if (!layout_supported || !ticket.matches(extent)) throw Error::Refused;
  return std::allocate_shared<T>(Allocator<T>(std::move(ticket)), std::forward<Args>(args)...);
}
} // namespace miniav::wgc_owner_storage
#undef MINIAV_KNOWN_OWNER_STORAGE
