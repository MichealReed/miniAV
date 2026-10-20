// Real production types/factories in this translation unit: no surrogate Owner
// and no test-only fields. Only unrelated capture/COM entrypoints abort below.
#include "../../windows/screen_context_win_wgc_strict.cpp"
#include "../../windows/wgc_platform_context.h"
#include <cstdio>
#include <cstdlib>
#include <malloc.h>

extern "C" int miniav_owner_storage_c_header_layout(void);
// None of these paths may run in a storage-only check. The real factory itself
// pins its defining module, but never initializes COM/GPU or launches a worker.
extern "C" int miniav_com_legacy_percall(void) { std::abort(); }
extern "C" void miniav_com_ensure_mta(void) { std::abort(); }
extern "C" int miniav_dispatch_guard_acquire_if_enabled(void) { std::abort(); }
extern "C" void miniav_dispatch_guard_release(void) { std::abort(); }
extern "C" void miniav_dispatch_set_enabled(int) { std::abort(); }
extern "C" void *miniav_calloc(size_t, size_t) { std::abort(); }
extern "C" void miniav_free(void *) { std::abort(); }
extern "C" void *miniav_wgc_strict_holder(MiniAVScreenContext *) { std::abort(); }

namespace {
struct HeapEvent { int kind; uintptr_t address; size_t bytes, alignment; };
HeapEvent heap_events[32]{};
bool observing = false;
size_t heap_count = 0;
int fail_allocation = 0;
void note(int kind, void *address, size_t bytes, size_t alignment) noexcept {
  if (!observing) return;
  if (heap_count >= 32) std::abort();
  heap_events[heap_count++] = {kind, reinterpret_cast<uintptr_t>(address), bytes, alignment};
}
void require(bool value, const char *message) {
  if (!value) { observing = false; std::fprintf(stderr, "FAIL %s\n", message); std::exit(1); }
}
void begin() { heap_count = 0; observing = true; }
void end() { observing = false; }
}
void *operator new(size_t bytes) {
  if (observing && fail_allocation && --fail_allocation == 0) {
    note(3, nullptr, bytes, __STDCPP_DEFAULT_NEW_ALIGNMENT__);
    throw std::bad_alloc();
  }
  void *value = std::malloc(bytes ? bytes : 1);
  if (!value) throw std::bad_alloc();
  note(1, value, bytes, __STDCPP_DEFAULT_NEW_ALIGNMENT__);
  return value;
}
void *operator new[](size_t bytes) { return ::operator new(bytes); }
void operator delete(void *value) noexcept {
  std::free(value); note(2, value, 0, __STDCPP_DEFAULT_NEW_ALIGNMENT__);
}
void operator delete(void *value, size_t) noexcept { ::operator delete(value); }
void operator delete[](void *value) noexcept { ::operator delete(value); }
void operator delete[](void *value, size_t) noexcept { ::operator delete(value); }
void *operator new(size_t bytes, std::align_val_t alignment) {
  auto value = _aligned_malloc(bytes, static_cast<size_t>(alignment));
  if (!value) throw std::bad_alloc();
  note(1, value, bytes, static_cast<size_t>(alignment));
  return value;
}
void operator delete(void *value, std::align_val_t alignment) noexcept {
  _aligned_free(value); note(2, value, 0, static_cast<size_t>(alignment));
}
void operator delete(void *value, size_t, std::align_val_t alignment) noexcept { ::operator delete(value, alignment); }

namespace {
using namespace miniav::wgc_owner_storage;
enum class Phase { Issued, Allocating, Allocated, Constructed, Disposed, Freeing, Freed, Cancelled };
struct Slot {
  Phase phase = Phase::Issued;
  Extent extent{};
  uintptr_t address = 0;
};
struct Fixture {
  std::atomic<int> references{0};
  Slot slots[4];
  size_t role_count = 2;
  uint64_t generation = 17, source_epoch = 29;
  bool admitted = true, terminal = false, quarantined = false;
  bool refuse_before_free = false, refuse_after_free = false;
  bool refuse_allocated = false;
  uint32_t refusal_role = 0;
  uint64_t cpu = 0, objects = 0;
  void init(const MiniAVWindowsStrictOwnerStorageProfileV1 &profile, bool allow = true) {
    role_count = 2;
    admitted = allow;
    for (size_t i = 0; i < 2; ++i) slots[i].extent = {profile.roles[i].requested_bytes, profile.roles[i].alignment};
    cpu = allow ? profile.total_requested_bytes : 0;
    objects = allow ? 2 : 0;
  }
  void init(const MiniAVWindowsStrictControlStorageProfileV1 &profile) {
    role_count = 4;
    for (size_t i = 0; i < 4; ++i) slots[i].extent = {profile.roles[i].requested_bytes, profile.roles[i].alignment};
    cpu = profile.total_requested_bytes;
    objects = 4;
  }
  void settle() noexcept {
    if (!terminal || quarantined) return;
    for (size_t i = 0; i < role_count; ++i)
      if (slots[i].phase != Phase::Freed && slots[i].phase != Phase::Cancelled) return;
    cpu = objects = 0;
  }
};
void retain(void *context) noexcept { static_cast<Fixture *>(context)->references.fetch_add(1); }
void release(void *context) noexcept {
  if (static_cast<Fixture *>(context)->references.fetch_sub(1) <= 0) std::abort();
}
uint32_t event(void *context, const EventRecord *record) noexcept {
  auto &f = *static_cast<Fixture *>(context);
  if (!record || record->size != sizeof(*record) || record->version != 1 ||
      record->role >= f.role_count || record->row != 0 || record->generation != f.generation ||
      record->source_epoch != f.source_epoch) return 0;
  auto &s = f.slots[record->role];
  if (record->bytes != s.extent.bytes || record->alignment != s.extent.alignment) return 0;
  const auto kind = static_cast<Event>(record->event);
  if (kind == Event::Quarantine) { f.quarantined = true; return 1; }
  if (f.quarantined) return 0;
  if (kind == Event::ColdScopeClosed) {
    if (record->role != 2 || record->address || f.role_count != 4) return 0;
    for (size_t i : {0u, 2u, 3u})
      if (f.slots[i].phase != Phase::Freed && f.slots[i].phase != Phase::Cancelled) return 0;
    f.terminal = true; f.settle(); return 1;
  }
  switch (kind) {
  case Event::BeginAllocation:
    if (!f.admitted || s.phase != Phase::Issued || record->address) return 0;
    s.phase = Phase::Allocating; break;
  case Event::Allocated:
    if (s.phase != Phase::Allocating || !record->address || record->address % s.extent.alignment ||
        (f.refuse_allocated && record->role == f.refusal_role)) return 0;
    s.address = record->address; s.phase = Phase::Allocated; break;
  case Event::Constructed:
    if (s.phase != Phase::Allocated || record->address) return 0;
    s.phase = Phase::Constructed; break;
  case Event::Disposed:
    if (s.phase != Phase::Constructed || record->address) return 0;
    s.phase = Phase::Disposed; break;
  case Event::BeginDeallocation:
    if (s.address != record->address ||
        (s.phase != Phase::Disposed && s.phase != Phase::Allocated) ||
        (record->role == f.refusal_role && f.refuse_before_free)) return 0;
    s.phase = Phase::Freeing; break;
  case Event::FreeReturned:
    if (s.phase != Phase::Freeing || s.address != record->address ||
        (record->role == f.refusal_role && f.refuse_after_free)) return 0;
    s.phase = Phase::Freed; break;
  case Event::AllocationFailed:
    if (s.phase != Phase::Allocating || record->address) return 0;
    s.phase = Phase::Cancelled; break;
  case Event::CancelUnallocated:
    if (s.phase != Phase::Issued || record->address) return 0;
    s.phase = Phase::Cancelled; break;
  default: return 0;
  }
  f.settle();
  return 1;
}
const Ops ops{retain, release, event};
Ticket ticket(Fixture &f, uint32_t role) {
  return Ticket::retain(&f, &ops, {f.generation, f.source_epoch, 0, role}, f.slots[role].extent);
}
MiniAVResultCode create(Fixture &f, void **out) {
  auto holder = ticket(f, 0), owner = ticket(f, 1);
  return miniav_wgc_strict_create_funded(nullptr, nullptr, nullptr, holder, owner, out);
}
bool allocation(size_t index, const Fixture &f, size_t role) {
  const auto &h = heap_events[index]; const auto &s = f.slots[role];
  return h.kind == 1 && h.address == s.address && h.bytes == s.extent.bytes &&
      h.address % s.extent.alignment == 0;
}
bool freed(size_t index, const Fixture &f, size_t role) {
  return heap_events[index].kind == 2 && heap_events[index].address == f.slots[role].address;
}
MiniAVWindowsStrictOwnerStorageProfileV1 profile() {
  MiniAVWindowsStrictOwnerStorageProfileV1 p{};
  p.struct_size = sizeof(p); p.abi_version = 1;
  require(MiniAV_Screen_Windows_GetStrictOwnerStorageProfileV1(&p) == 0, "qualified original profile");
  return p;
}

void header_cases() {
  require(miniav_owner_storage_c_header_layout() == 1, "C header layout");
  uint32_t short_record[2]{8, 1};
  require(MiniAV_Screen_Windows_GetStrictOwnerStorageProfileV1(
      reinterpret_cast<MiniAVWindowsStrictOwnerStorageProfileV1 *>(short_record)) == MINIAV_ERROR_INVALID_ARG &&
      short_record[0] == 8 && short_record[1] == 1, "short prefix untouched");
  MiniAVWindowsStrictOwnerStorageProfileV1 bad{};
  bad.struct_size = sizeof(bad); bad.abi_version = 2; bad.reserved0 = 0xabcdef;
  require(MiniAV_Screen_Windows_GetStrictOwnerStorageProfileV1(&bad) == MINIAV_ERROR_INVALID_ARG &&
      bad.reserved0 == 0xabcdef, "new version untouched");
  require(MiniAV_Screen_Windows_GetStrictOwnerStorageProfileV1(nullptr) == MINIAV_ERROR_INVALID_ARG,
      "null profile");
}

void selection_copy_cases(const MiniAVWindowsStrictOwnerStorageProfileV1 &p) {
  static Fixture selection_fixture;
  selection_fixture.init(p);
  void *holder = nullptr;
  begin();
  require(create(selection_fixture, &holder) == 0, "original selection storage owner");
  auto owner = get(holder);
  const auto allocated = heap_count;
  // Inert selection metadata only; Begin/worker/process/WinRT are not entered.
  owner->mode = Mode::strict;
  owner->nonce = {sizeof(owner->nonce), 1, {1}};
  for (uint64_t id = 1; id <= max_window_candidates; ++id) {
    auto *candidate = owner->append_candidate();
    require(candidate != nullptr, "fixed native selection slot");
    candidate->public_value = {sizeof(candidate->public_value), 1, id, id + 100,
        17, 0, 18, {}};
    std::memcpy(candidate->public_value.title_utf8, "Ocean", 6);
  }
  MiniAVWindowsScreenCandidateV1 candidate{};
  for (uint32_t index = 0; index < max_window_candidates; ++index) {
    require(miniav_wgc_strict_copy_candidate(holder, &owner->nonce, index, &candidate) == 0 &&
        candidate.candidate_id == index + 1 && candidate.hwnd_value == index + 101 &&
        std::strcmp(candidate.title_utf8, "Ocean") == 0, "actual original nonce/index value copy");
  }
  auto wrong_nonce = owner->nonce; wrong_nonce.nonce[0] ^= 1;
  require(miniav_wgc_strict_copy_candidate(holder, &wrong_nonce, 0, &candidate) ==
      MINIAV_ERROR_PERMISSION_DENIED, "another selection nonce refused");
  require(miniav_wgc_strict_copy_candidate(holder, &owner->nonce, max_window_candidates,
      &candidate) == MINIAV_ERROR_INVALID_ARG, "selection index overflow refused");
  owner->operations = 1;
  require(miniav_wgc_strict_copy_candidate(holder, &owner->nonce, 0, &candidate) ==
      MINIAV_ERROR_INVALID_OPERATION, "active operation blocks selection copy");
  owner->operations = 0; owner->nonce_spent = true;
  require(miniav_wgc_strict_copy_candidate(holder, &owner->nonce, 0, &candidate) ==
      MINIAV_ERROR_INVALID_OPERATION, "consumed selection refused");
  owner->nonce_spent = false; owner->candidates[0].closed = true;
  require(miniav_wgc_strict_copy_candidate(holder, &owner->nonce, 0, &candidate) ==
      MINIAV_ERROR_DEVICE_LOST, "closed window metadata refused");
  owner->candidates[0].closed = false;
  owner->selection_deadline = GetTickCount64() - 1;
  require(miniav_wgc_strict_copy_candidate(holder, &owner->nonce, 0, &candidate) ==
      MINIAV_ERROR_INVALID_OPERATION && owner->terminal, "expired selection fences copy");
  owner->state = 2; // Only inert refs/counters in this CPU fixture, no native join proof.
  require(heap_count == allocated, "selection copy and refusals have no C++ heaps");
  require(miniav_wgc_strict_delete(holder) == 0, "selection fixture holder disposal");
  owner.reset();
  end();
  selection_fixture.terminal = true; selection_fixture.settle();
  require(selection_fixture.cpu == 0 && selection_fixture.references == 0,
      "selection storage original final-free custody");

  // Public ABI malformed calls exercise short-output sentinels without a real
  // platform/context lookup; no native activation is permitted in this witness.
  MiniAVWindowsAppAdmissionV1 admission{};
  admission.struct_size = sizeof(admission); admission.abi_version = 1;
  MiniAVWindowsSelectionNonceV1 nonce{sizeof(nonce), 1, {99}};
  uint32_t count = 99;
  require(MiniAV_Screen_Windows_BeginStrictSelectionV2(nullptr, &admission, &nonce,
      &count) == MINIAV_ERROR_INVALID_ARG && count == 0 && nonce.struct_size == 0,
      "public V2 invalid input clears outputs");
  struct { uint32_t size, version, guard0, guard1; } short_out{8, 1, 0x1234, 0x5678};
  nonce = {sizeof(nonce), 1, {1}};
  require(MiniAV_Screen_Windows_CopyStrictSelectionCandidateV1(nullptr, &nonce, 0,
      reinterpret_cast<MiniAVWindowsScreenCandidateV1 *>(&short_out)) == MINIAV_ERROR_INVALID_ARG &&
      short_out.size == 0 && short_out.version == 0 && short_out.guard0 == 0x1234 &&
      short_out.guard1 == 0x5678, "public copy bounded short-output clear");
  std::puts("PASS allocation-free selection copy: original nonce, 128 records, fences, bounded outputs and final free");
}

void delegate_uncertainty_cases(const MiniAVWindowsStrictOwnerStorageProfileV1 &p) {
  static Fixture final_release;
  final_release.init(p);
  void *last_holder = nullptr;
  begin();
  require(create(final_release, &last_holder) == 0, "actual final COM release owner");
  auto retained = get(last_holder);
  auto last_handler = retained->frame_callback();
  require(miniav_wgc_strict_delete(last_holder) == 0 && heap_count == 3 &&
      freed(2, final_release, 0), "original public holder really freed");
  retained.reset(); // No strong/weak caller aliases; only the handler/storage keeper remain.
  last_handler = nullptr;
  require(heap_count == 4 && freed(3, final_release, 1),
      "actual last COM release completes class-delete epilogue before original final free");
  end();
  final_release.terminal = true; final_release.settle();
  require(final_release.cpu == 0 && final_release.references == 0,
      "final COM-only lifetime settles its actual original allocation");

  static Fixture original;
  static void *quarantined_holder = nullptr;
  original.init(p);
  begin();
  require(create(original, &quarantined_holder) == 0, "actual delegate uncertainty owner");
  auto owner = get(quarantined_holder);
  owner->mode = Mode::strict; // Inert mode marker; no worker/process/source entry.
  auto handler = owner->frame_callback();
  require(owner->delegates == 1 && heap_count == 2, "actual in-owner uncertainty handler");
  // Metadata refusal marker only, not actual heap corruption/OS failure evidence.
  owner->frame_delegate.header.bytes += 1;
  handler = nullptr; // Actual WinRT last Release/destructor/class delete.
  require(owner->delegates == 0 && owner->state == 3 &&
      owner->frame_delegate.header.phase.load() == delegate_storage::Phase::quarantined &&
      owner->frame_delegate.header.keeper.get() == owner.get() && heap_count == 2,
      "unknown actual delete preserves original storage/owner and quarantines source");
  require(miniav_wgc_strict_prepare_destroy(quarantined_holder) != 0 &&
      get(quarantined_holder) == owner, "unknown delete keeps readable native holder");
  auto weak = std::weak_ptr<Owner>(owner);
  owner.reset();
  require(!weak.expired() && original.cpu == p.total_requested_bytes && original.references > 0,
      "uncertain delegate cannot refund its original budget");
  end();
  std::puts("PASS actual WinRT last Release: final physical free with no caller aliases, and original keeper/debt retained on uncertainty");
}

void frame_slot_cases(const MiniAVWindowsStrictOwnerStorageProfileV1 &p) {
  static Fixture exact_frames, other_frames, uncertain_frames;
  exact_frames.init(p); other_frames.init(p); uncertain_frames.init(p);
  void *first = nullptr, *other = nullptr, *uncertain = nullptr;
  begin();
  require(create(exact_frames, &first) == 0 && create(other_frames, &other) == 0,
      "real frame-pool original owners");
  auto owner = get(first);
  const auto initial_heaps = heap_count;
  auto wrap = [](const Holder &value, int64_t timestamp) {
    require(value->prepare_pending(), "empty pending envelope preparation");
    value->pending->width = 64; value->pending->height = 32;
    value->pending->timestamp = timestamp;
    // Inert completion metadata only: no native refs/handles/work exist here.
    value->pending->issued = true;
    require(!value->wrap_pending_frame() && value->pending,
        "unfinished work cannot enter an envelope");
    value->pending->complete = true;
    return value->wrap_pending_frame();
  };
  FrameSlot *slots[max_outstanding_buffers]{};
  const auto address = reinterpret_cast<uintptr_t>(owner.get());
  for (size_t i = 0; i < max_outstanding_buffers; ++i) {
    auto *slot = wrap(owner, i + 1);
    require(slot && !owner->pending && slot->phase == FramePhase::ready,
        "actual native envelope committed after inert completion");
    const auto slot_address = reinterpret_cast<uintptr_t>(slot);
    require(slot_address >= address && slot_address + sizeof(*slot) <= address + sizeof(Owner) &&
        slot->buffer.internal_handle == &slot->internal &&
        slot->internal.native_singular_resource_ptr == &slot->payload &&
        slot->internal.parent_miniav_buffer_ptr == &slot->buffer &&
        slot->payload.owner == owner && slot->buffer.timestamp_us == static_cast<int64_t>(i + 1),
        "complete envelope/backlinks physically inside paid original owner");
    slots[i] = slot;
  }
  require(owner->buffers == max_outstanding_buffers && !wrap(owner, 99) &&
      owner->pending && owner->pending->timestamp == 99,
      "full pool refuses without replacing occupied or pending ownership");
  owner->pending.reset(); // Empty native fixture refs, never a GPU completion proof.
  MiniAVNativeBufferInternalPayload foreign_payload{};
  require(owner->release_payload(&foreign_payload) == MINIAV_ERROR_INVALID_HANDLE &&
      miniav_wgc_strict_release(other, &slots[0]->internal) == MINIAV_ERROR_INVALID_HANDLE &&
      owner->buffers == max_outstanding_buffers,
      "foreign pointers/original-owner mismatch cannot release a slot");
  auto *saved_backlink = slots[0]->internal.parent_miniav_buffer_ptr;
  slots[0]->internal.parent_miniav_buffer_ptr = nullptr;
  require(owner->release_payload(&slots[0]->internal) == MINIAV_ERROR_INVALID_HANDLE &&
      slots[0]->phase == FramePhase::ready, "altered backlink retains envelope");
  slots[0]->internal.parent_miniav_buffer_ptr = saved_backlink;
  require(miniav_wgc_strict_release(first, &slots[0]->internal) == MINIAV_SUCCESS &&
      owner->release_payload(&slots[0]->internal) == MINIAV_ERROR_INVALID_OPERATION &&
      owner->buffers == max_outstanding_buffers - 1,
      "actual release returns one slot once while context is valid");
  for (int i = 0; i < 256; ++i) {
    auto *slot = wrap(owner, i + 100);
    require(slot == slots[0] && slot->buffer.timestamp_us == i + 100 &&
        owner->release_payload(&slot->internal) == MINIAV_SUCCESS,
        "returned frame slot reused with a fresh complete envelope");
  }
  require(heap_count == initial_heaps,
      "actual bounded frame prepare/wrap/release/reuse has zero operation heaps");
  auto weak = std::weak_ptr<Owner>(owner);
  exact_frames.terminal = true; // Fixture-only never-launched original scope.
  require(miniav_wgc_strict_delete(first) == MINIAV_SUCCESS, "public frame-owner holder free");
  owner.reset();
  require(!weak.expired(), "outstanding envelopes retain owner without public holder");
  for (size_t i = 1; i < max_outstanding_buffers; ++i) {
    auto retained = weak.lock();
    require(retained && retained->release_payload(&slots[i]->internal) == MINIAV_SUCCESS,
        "real release helper returns last self-retaining frame slots");
  }
  require(weak.expired() && exact_frames.cpu == p.total_requested_bytes,
      "last frame release ends payload but weak storage remains charged");
  weak.reset();
  require(exact_frames.cpu == 0 && exact_frames.references == 0,
      "actual final owner free settles original frame-pool storage");
  other_frames.terminal = true;
  require(miniav_wgc_strict_delete(other) == MINIAV_SUCCESS && other_frames.cpu == 0,
      "unrelated original owner remains independently releasable");
  end();

  begin();
  require(create(uncertain_frames, &uncertain) == MINIAV_SUCCESS, "uncertain frame owner");
  owner = get(uncertain);
  auto *valid = wrap(owner, 1);
  auto *failed = wrap(owner, 2);
  require(valid && failed, "independent valid and uncertain frame slots");
  failed->payload.release_failed = true; // Earlier failure marker, no foreign HANDLE.
  require(miniav_wgc_strict_release(uncertain, &failed->internal) == MINIAV_ERROR_SYSTEM_CALL_FAILED &&
      failed->phase == FramePhase::quarantined && owner->buffers == 2 &&
      failed->payload.owner == owner && owner->state == 3,
      "uncertain release keeps its self-retention, slot and original debt");
  require(miniav_wgc_strict_release(uncertain, &valid->internal) == MINIAV_SUCCESS &&
      valid->phase == FramePhase::empty && owner->buffers == 1,
      "another slot's quarantine cannot turn consumed release into retryable failure");
  require(!owner->prepare_frame() &&
      miniav_wgc_strict_release(uncertain, &failed->internal) == MINIAV_ERROR_SYSTEM_CALL_FAILED,
      "quarantined source/slot cannot admit or retry native release");
  auto retained_weak = std::weak_ptr<Owner>(owner);
  uncertain_frames.terminal = true;
  require(miniav_wgc_strict_delete(uncertain) == MINIAV_SUCCESS, "uncertain holder disposal");
  owner.reset();
  require(!retained_weak.expired() && uncertain_frames.cpu == p.total_requested_bytes &&
      uncertain_frames.references > 0,
      "unknown envelope keeps real owner storage and original debt after holder disposal");
  end();
  std::puts("PASS actual fixed envelope pool: capacity3, original ownership/backlinks, zero operation heaps, reuse, final weak/free and unknown retention");
}
}

#include "control_storage_cpu.h"

int main() {
  header_cases();
#ifdef MINIAV_OWNER_STORAGE_FORCE_UNSUPPORTED
  MiniAVWindowsStrictOwnerStorageProfileV1 p{};
  p.struct_size = sizeof(p); p.abi_version = 1;
  void *out = reinterpret_cast<void *>(1);
  begin();
  const auto queried = MiniAV_Screen_Windows_GetStrictOwnerStorageProfileV1(&p);
  const auto created = miniav_wgc_strict_create_funded(nullptr, nullptr, nullptr, {}, {}, &out);
  end();
  require(queried == MINIAV_ERROR_NOT_SUPPORTED && created == MINIAV_ERROR_NOT_SUPPORTED &&
      !out && !p.struct_size && heap_count == 0, "unsupported whole query/factory zero allocations");
  unsupported_control_case();
  std::puts("PASS unsupported native pair query/factory before heap or dependencies");
#else
  const auto p = profile();
  require(p.struct_size == 128 && p.abi_version == 1 && p.factory_revision == 1 && p.flags == 3 &&
      p.role_count == 2 && p.additional_resources == 2 && !p.reserved0 &&
      p.roles[0].kind == 0 && p.roles[1].kind == 1 &&
      p.total_requested_bytes == p.roles[0].requested_bytes + p.roles[1].requested_bytes,
      "canonical two-role profile");
  struct Extended { MiniAVWindowsStrictOwnerStorageProfileV1 p; uint64_t suffix; } extended{p, 0x12345678};
  extended.p.struct_size = sizeof(extended);
  require(MiniAV_Screen_Windows_GetStrictOwnerStorageProfileV1(&extended.p) == 0 &&
      extended.suffix == 0x12345678, "unknown output suffix preserved");

  // Fixtures persist through intentional quarantine. These test-only callbacks
  // are not the SDK budget bridge or native source-worker join authority.
  static Fixture exact, denied, wrong, foreign, allocation_failure[2], before_free, after_free;
  exact.init(p);
  begin();
  void *value = nullptr;
  require(create(exact, &value) == 0 && value, "real funded pair construction");
  require(heap_count == 2 && allocation(0, exact, 1) && allocation(1, exact, 0), "two exact original allocations");
  auto alias = get(value);
  // The real quoted Owner contains all stable candidate slots and the pending
  // state. These operations use no substitute payload, COM or capture entry.
  require(!alias->find_candidate(0) && !alias->find_candidate(1),
      "unpopulated/zero candidate identity refuses");
  Candidate *candidate_slots[max_window_candidates]{};
  const auto owner_address = reinterpret_cast<uintptr_t>(alias.get());
  for (size_t i = 0; i < max_window_candidates; ++i) {
    auto *candidate = alias->append_candidate();
    require(candidate && !candidate->item && !candidate->registered &&
        !candidate->closed.load(), "real inline candidate initialization");
    candidate->public_value.candidate_id = i + 1;
    const auto address = reinterpret_cast<uintptr_t>(candidate);
    require(address >= owner_address &&
        address + sizeof(*candidate) <= owner_address + sizeof(Owner),
        "candidate physically inside paid original owner");
    candidate_slots[i] = candidate;
  }
  require(!alias->append_candidate() &&
      alias->candidate_count == max_window_candidates &&
      !alias->find_candidate(0) && !alias->find_candidate(max_window_candidates + 1),
      "candidate capacity and unknown identity refuse without reuse");
  for (size_t i = 0; i < max_window_candidates; ++i)
    require(alias->find_candidate(i + 1) == candidate_slots[i],
        "all candidate addresses remain stable through full population");
  for (int i = 0; i < 256; ++i) {
    require(alias->prepare_pending(), "inline pending state prepares when empty");
    auto *pending = &*alias->pending;
    const auto address = reinterpret_cast<uintptr_t>(pending);
    require(address >= owner_address &&
        address + sizeof(*pending) <= owner_address + sizeof(Owner),
        "pending state physically inside paid original owner");
    pending->width = 37;
    require(!alias->prepare_pending() && &*alias->pending == pending &&
        pending->width == 37, "occupied pending state is never overwritten");
    // All native handles/references remain null in this storage-only case.
    alias->pending.reset();
  }
  using ClosedCallback = decltype(alias->closed_callback(candidate_slots[0]));
  static_assert(sizeof(DelegateTicket) == sizeof(Holder));
  static_assert(std::is_copy_constructible_v<DelegateTicket> &&
      std::is_nothrow_move_constructible_v<DelegateTicket> &&
      !std::is_copy_assignable_v<DelegateTicket> &&
      !std::is_move_assignable_v<DelegateTicket>);
  std::optional<ClosedCallback> registered_delegate, late_delegate;
  registered_delegate.emplace(alias->closed_callback(candidate_slots[0]));
  const auto closed_address = winrt::get_abi(*registered_delegate);
  require(closed_address == candidate_slots[0]->delegate.address() && alias->delegates == 1,
      "actual WinRT Closed object in original paid slot, one ticket");
  {
    auto *abi = reinterpret_cast<winrt::impl::abi_t<ClosedEvent> *>(closed_address);
    void *queried = nullptr;
    require(abi->QueryInterface(winrt::guid_of<ClosedEvent>(), &queried) == 0 &&
        queried == closed_address, "actual typed QueryInterface identity");
    reinterpret_cast<winrt::impl::abi_t<ClosedEvent> *>(queried)->Release();
    const winrt::guid missing{};
    queried = reinterpret_cast<void *>(1);
    require(abi->QueryInterface(missing, &queried) == E_NOINTERFACE && !queried,
        "unsupported QueryInterface clears output without a marshaller");
  }
  {
    auto copy = *registered_delegate;
    require(alias->delegates == 1, "COM aliases retain one actual Closed object/ticket");
    late_delegate.emplace(std::move(copy));
    require(!copy && alias->delegates == 1, "COM move transfers the interface reference");
  }
  require(alias->delegates == 1, "moved-from interface destruction is harmless");
  registered_delegate.reset();
  require(alias->delegates == 1, "queued Closed copy survives original removal");
  {
    // Actual production WinRT object, but no event registration/apartment/frame.
    auto frame = alias->frame_callback();
    require(winrt::get_abi(frame) == alias->frame_delegate.address(),
        "actual FrameArrived object is inside original paid storage");
    auto copy = frame;
    auto moved = std::move(copy);
    require(!copy && alias->delegates == 2, "actual FrameArrived COM copy/move custody");
    moved(Direct3D11CaptureFramePool{nullptr}, winrt::Windows::Foundation::IInspectable{nullptr});
    require(alias->frame_ready && alias->callbacks == 0,
        "production frame signal enters and retires its invocation");
  }
  require(alias->delegates == 1 && heap_count == 2 &&
      alias->frame_delegate.header.phase.load() == delegate_storage::Phase::freed &&
      !alias->frame_delegate.header.keeper,
      "actual delegate construction/COM references/invocation/delete use no operation heaps");
  {
    bool refused = false;
    try { auto reused = alias->frame_callback(); } catch (const std::bad_alloc &) { refused = true; }
    require(refused && alias->delegates == 1 && heap_count == 2 && !delegate_storage::current,
        "freed delegate slots never recycle and scoped cursor unwinds");
    refused = false;
    try { FrameCallable::operator new(sizeof(FrameDelegate)); }
    catch (const std::bad_alloc &) { refused = true; }
    require(refused && heap_count == 2, "unscoped delegate allocation refuses before heap");
    Candidate foreign_candidate;
    refused = false;
    try { auto foreign_callback = alias->closed_callback(&foreign_candidate); }
    catch (const std::bad_alloc &) { refused = true; }
    require(refused && alias->delegates == 1 && heap_count == 2,
        "foreign candidate cannot borrow original source delegate storage");
    {
      auto &spare = candidate_slots[1]->delegate;
      delegate_storage::Scope<ClosedDelegate> scope(spare, alias, unknown_delegate_storage);
      refused = false;
      try { FrameCallable::operator new(sizeof(FrameDelegate)); }
      catch (const std::bad_alloc &) { refused = true; }
      require(refused && spare.header.phase.load() == delegate_storage::Phase::fresh,
          "a different handler family cannot consume the scoped slot");
      refused = false;
      try { ClosedCallable::operator new(sizeof(ClosedDelegate) + 1); }
      catch (const std::bad_alloc &) { refused = true; }
      require(refused && spare.header.phase.load() == delegate_storage::Phase::fresh &&
          !spare.header.keeper && heap_count == 2,
          "wrong body size refuses before slot/heap custody");
    }
  }
  {
    std::array<ClosedEvent, max_window_candidates - 1> other_handlers{};
    for (size_t i = 1; i < max_window_candidates; ++i) {
      other_handlers[i - 1] = alias->closed_callback(candidate_slots[i]);
      require(winrt::get_abi(other_handlers[i - 1]) == candidate_slots[i]->delegate.address(),
          "every actual Closed object occupies its own original slot");
    }
    require(alias->delegates == max_window_candidates && heap_count == 2,
        "all128 actual native Closed bodies fit without operation heaps");
  }
  require(alias->delegates == 1 && heap_count == 2, "all extra actual COM handler releases settle");
  auto weak = std::weak_ptr<Owner>(alias);
  auto second_weak = weak;
  require(!alias->worker_started && !alias->worker.joinable() && !alias->parent && !alias->platform,
      "genuine cold owner, no worker/context");
  exact.terminal = true; // fixture-only genuine never-launched scope
  require(miniav_wgc_strict_claim_generic(value) == MINIAV_ERROR_INVALID_OPERATION,
      "no funded generic fallback");
  require(miniav_wgc_strict_delete(value) == 0 && heap_count == 3 && freed(2, exact, 0), "holder actual free");
  alias.reset();
  require(!weak.expired() && heap_count == 3,
      "late delegate retains actual owner after public holder/alias release");
  (*late_delegate)(GraphicsCaptureItem{nullptr}, winrt::Windows::Foundation::IInspectable{nullptr});
  {
    auto retained = weak.lock();
    require(retained && candidate_slots[0]->closed.load() &&
        retained->callbacks == 0 && retained->delegates == 1 && heap_count == 3,
        "late copied production Closed callable retains slot and retires invocation");
  }
  late_delegate.reset();
  require(weak.expired() && heap_count == 3 && exact.cpu == p.total_requested_bytes, "last-strong not physical free");
  weak.reset();
  require(heap_count == 3 && exact.cpu == p.total_requested_bytes, "second weak retains whole pair debt");
  second_weak.reset();
  end();
  require(heap_count == 4 && freed(3, exact, 1) && exact.cpu == 0 && exact.objects == 0 &&
      exact.references == 0, "actual final free settles without authority cycle");

  // Same common wrapper for the existing unscoped path; this remains a cold
  // constructor/claim/destructor check and never invokes generic capture.
  begin();
  value = miniav_wgc_strict_create(nullptr, nullptr, nullptr);
  require(value && !get(value)->worker_started &&
      miniav_wgc_strict_claim_generic(value) == 0, "legacy cold owner remains usable");
  require(miniav_wgc_strict_delete(value) == 0, "legacy checked disposal");
  end();
  require(heap_count == 4, "legacy owner and wrapper matching allocation/free");

  // Actual platform constructors run, including explicit C++17 atomic
  // initialization and null WinRT/COM wrappers. No native activation follows.
  begin();
  auto *platform = miniav::wgc_platform_storage::allocate();
  require(platform && !platform->d3d_device && !platform->d3d_context &&
      !platform->d3d_device_winrt && !platform->capture_item && !platform->frame_pool &&
      !platform->session && platform->is_streaming.load() == FALSE &&
      platform->callbacks_in_flight.load() == 0 && platform->lost_cb_fired.load() == FALSE &&
      !platform->strict_holder && !platform->stop_event_handle && !platform->parent_ctx &&
      !platform->selected_hwnd && !platform->selected_item_id[0], "real cold platform initialization");
  require(heap_count == 1 && heap_events[0].bytes == sizeof(*platform) &&
      heap_events[0].address == reinterpret_cast<uintptr_t>(platform), "real platform allocation extent");
  const auto platform_address = reinterpret_cast<uintptr_t>(platform);
  miniav::wgc_platform_storage::destroy(platform);
  end();
  require(heap_count == 2 && heap_events[1].kind == 2 &&
      heap_events[1].address == platform_address, "matched C++ platform destruction/free");

  denied.init(p, false); wrong.init(p); foreign.init(p);
  auto bad_holder = Ticket::retain(&wrong, &ops, {wrong.generation, wrong.source_epoch, 0, 0},
      {p.roles[0].requested_bytes + 8, p.roles[0].alignment});
  auto good_owner = ticket(wrong, 1), foreign_holder = ticket(foreign, 0);
  auto foreign_epoch = Ticket::retain(&wrong, &ops,
      {wrong.generation, wrong.source_epoch + 1, 0, 0}, wrong.slots[0].extent);
  begin();
  value = reinterpret_cast<void *>(1);
  require(create(denied, &value) == MINIAV_ERROR_INVALID_OPERATION && !value, "original allowance refusal");
  require(miniav_wgc_strict_create_funded(nullptr, nullptr, nullptr, bad_holder, good_owner, &value) ==
      MINIAV_ERROR_INVALID_ARG && !value, "wrong extent before either heap");
  require(miniav_wgc_strict_create_funded(nullptr, nullptr, nullptr, foreign_holder, good_owner, &value) ==
      MINIAV_ERROR_INVALID_ARG && !value, "cross-original-domain refused");
  require(miniav_wgc_strict_create_funded(nullptr, nullptr, nullptr, foreign_epoch, good_owner, &value) ==
      MINIAV_ERROR_INVALID_ARG && !value, "same domain with another source epoch refused");
  end();
  require(heap_count == 0 && denied.references == 0, "all preallocation refusals allocate nothing");

  for (int failed = 1; failed <= 2; ++failed) {
    auto &f = allocation_failure[failed - 1]; f.init(p);
    begin(); fail_allocation = failed;
    require(create(f, &value) == MINIAV_ERROR_OUT_OF_MEMORY && !value, "actual heap failure rollback");
    end(); fail_allocation = 0;
    f.terminal = true; f.settle();
    require(f.cpu == 0 && f.references == 0 &&
        (failed == 1 ? heap_count == 1 && heap_events[0].kind == 3 :
         heap_count == 3 && allocation(0, f, 1) && heap_events[1].kind == 3 && freed(2, f, 1)),
        "failed attempt and genuine final free/cancel exactly once");
  }

  before_free.init(p); before_free.refuse_before_free = true;
  begin();
  require(create(before_free, &value) == 0, "pre-free fault fixture");
  auto retained = get(value);
  require(miniav_wgc_strict_delete(value) == MINIAV_ERROR_SYSTEM_CALL_FAILED &&
      get(value) == retained, "failed release preserves readable owner");
  end();
  retained.reset();
  require(heap_count == 2 && before_free.quarantined && before_free.cpu == p.total_requested_bytes &&
      before_free.references > 0, "pre-free uncertainty retains original authority and both heaps");

  after_free.init(p); after_free.refuse_after_free = true;
  begin();
  require(create(after_free, &value) == 0, "post-free fault fixture");
  retained = get(value);
  require(miniav_wgc_strict_delete(value) == 0, "post-free receipt refusal still consumes pointer");
  end();
  require(heap_count == 3 && freed(2, after_free, 0), "post-free actual deallocation witnessed");
  retained.reset();
  after_free.terminal = true; after_free.settle();
  require(after_free.quarantined && after_free.cpu == p.total_requested_bytes && after_free.references > 0,
      "post-free uncertainty keeps original debt, no retry or refund");
  std::printf("PASS native owner pair: holder=%llu/%u shared_owner=%llu/%u total=%llu resources=2\n",
      static_cast<unsigned long long>(p.roles[0].requested_bytes), p.roles[0].alignment,
      static_cast<unsigned long long>(p.roles[1].requested_bytes), p.roles[1].alignment,
      static_cast<unsigned long long>(p.total_requested_bytes));
  std::puts("Actual common factories, strong/weak/final-free, original-domain/refusal, allocation-failure and consumed/retained-pointer cases");
  std::puts("Inline candidate128/pending1: stable bounded addresses, zero operation heaps, occupied/overflow refusal and late original-ticket callback");
  std::puts("Actual WinRT Closed/FrameArrived objects: in-owner storage, COM aliases/QueryInterface/Invoke/last Release, late copy and zero operation heaps");
  std::puts("CPU storage/cold platform only; no SDK budget bridge, WinRT registration/OS COM activation, GPU/worker/window/capture or physical admission");
  selection_copy_cases(p);
  delegate_uncertainty_cases(p);
  frame_slot_cases(p);
  control_cases();
#endif
}
