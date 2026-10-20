// Original-budget cold bootstrap. No COM, dispatcher, D3D, registry, worker,
// source selection or capture entry is reachable from these constructors.
#include "screen_context_win_wgc_strict.h"
#include "wgc_platform_context.h"
#include <cstddef>
#include <type_traits>

namespace {
using namespace miniav::wgc_owner_storage;
struct ControlContext {
  MiniAVScreenContext value{};
  Ticket ticket;
  explicit ControlContext(Ticket funding) noexcept : ticket(std::move(funding)) {
    value.strict_control_owner = this;
  }
};
static_assert(std::is_standard_layout_v<ControlContext>);
static_assert(offsetof(ControlContext, value) == 0);
static_assert(std::is_nothrow_destructible_v<ControlContext>);

// Non-OK preserves the original allocation as a readable, quarantined owner.
// Children already consumed stay cleared. Never hand this to generic fallback.
MiniAVResultCode release_storage(ControlContext *context) noexcept {
  auto &base = context->value;
  if (base.strict_control_owner != context || base.ops || base.is_running ||
      base.is_configured || !context->ticket.role(2)) return MINIAV_ERROR_INVALID_ARG;
  auto *platform = static_cast<WGCScreenPlatformContext *>(base.platform_ctx);
  if (platform) {
    if (platform->ctx_magic || platform->parent_ctx != &base ||
        !platform->storage_ticket.role(3) ||
        !context->ticket.same_transaction(platform->storage_ticket))
      return MINIAV_ERROR_INVALID_OPERATION;
    if (platform->strict_holder) {
      const auto result = miniav_wgc_strict_delete(platform->strict_holder);
      if (result != MINIAV_SUCCESS) return result;
      platform->strict_holder = nullptr;
    }
    Ticket ticket = platform->storage_ticket;
    platform->~WGCScreenPlatformContext();
    const bool disposed = ticket.notify(Event::Disposed);
    if (!disposed || !ticket.begin_free(platform, sizeof(*platform), alignof(WGCScreenPlatformContext))) {
      // Only the cold constructor can produce this handle, so all other C++
      // members are genuinely empty. No native teardown is being guessed.
      ::new (static_cast<void *>(platform)) WGCScreenPlatformContext{};
      platform->parent_ctx = &base;
      platform->storage_ticket = ticket;
      if (!disposed) ticket.quarantine();
      return MINIAV_ERROR_SYSTEM_CALL_FAILED;
    }
    ticket.free_returned(platform, alignof(WGCScreenPlatformContext));
    base.platform_ctx = nullptr;
  }
  Ticket ticket = context->ticket;
  const MiniAVScreenContext saved = base;
  context->~ControlContext();
  const bool disposed = ticket.notify(Event::Disposed);
  if (!disposed || !ticket.begin_free(context, sizeof(*context), alignof(ControlContext))) {
    ::new (static_cast<void *>(context)) ControlContext(ticket);
    context->value = saved;
    if (!disposed) ticket.quarantine();
    return MINIAV_ERROR_SYSTEM_CALL_FAILED;
  }
  ticket.free_returned(context, alignof(ControlContext));
  // Committed consumption: no error can make this freed pointer retryable.
  return MINIAV_SUCCESS;
}

bool valid_authority(const MiniAVWindowsStrictControlStorageAuthorityV1 *a,
    const MiniAVWindowsStrictControlStorageProfileV1 &p) noexcept {
  if (!a || a->struct_size != sizeof(*a) || a->abi_version != 1 || !a->context ||
      !a->ops || !a->ops->retain || !a->ops->release || !a->ops->event ||
      !a->generation || !a->source_epoch || a->role_count != 4 || a->reserved0)
    return false;
  for (size_t i = 0; i < 4; ++i) {
    if (a->roles[i].reserved0 || a->roles[i].requested_bytes != p.roles[i].requested_bytes ||
        a->roles[i].alignment != p.roles[i].alignment) return false;
  }
  return true;
}
struct BuildFailure { MiniAVResultCode result; };
}

MiniAVResultCode miniav_wgc_strict_control_storage_profile(
    MiniAVWindowsStrictControlStorageProfileV1 *out) {
  if (!out) return MINIAV_ERROR_INVALID_ARG;
  *out = {};
  MiniAVWindowsStrictOwnerStorageProfileV1 pair{};
  const auto status = miniav_wgc_strict_owner_storage_profile(&pair);
  if (status != MINIAV_SUCCESS) return status;
  out->struct_size = sizeof(*out);
  out->abi_version = out->factory_revision = 1;
  out->flags = 3;
  identity(out->build_identity);
  out->role_count = 4;
  out->additional_resources = 2; // Base/platform already occupy two positions.
  out->roles[0] = pair.roles[0];
  out->roles[1] = pair.roles[1];
  out->roles[2] = {2, alignof(ControlContext), sizeof(ControlContext), 0};
  out->roles[3] = {3, alignof(WGCScreenPlatformContext), sizeof(WGCScreenPlatformContext), 0};
  for (const auto &role : out->roles) {
    if (out->total_requested_bytes > UINT64_MAX - role.requested_bytes) {
      *out = {}; return MINIAV_ERROR_NOT_SUPPORTED;
    }
    out->total_requested_bytes += role.requested_bytes;
  }
  return MINIAV_SUCCESS;
}

MiniAVResultCode miniav_wgc_strict_control_create(
    const MiniAVWindowsStrictControlStorageAuthorityV1 *authority,
    MiniAVWindowsStrictControlStorageOutcomeV1 *out) {
  // Public wrapper validates/initializes the fixed outcome before this entry.
  MiniAVWindowsStrictControlStorageProfileV1 profile{};
  auto result = miniav_wgc_strict_control_storage_profile(&profile);
  if (result != MINIAV_SUCCESS) return result;
  // Validate every extent before even retaining a callback reference.
  if (!valid_authority(authority, profile)) return MINIAV_ERROR_INVALID_ARG;
  out->generation = authority->generation;
  out->source_epoch = authority->source_epoch;
  out->row = authority->row;
  Ticket tickets[4];
  for (uint32_t i = 0; i < 4; ++i) {
    tickets[i] = Ticket::retain(authority->context, authority->ops,
        {authority->generation, authority->source_epoch, authority->row, i},
        {profile.roles[i].requested_bytes, profile.roles[i].alignment});
  }
  ControlContext *context = nullptr;
  {
    Pending p0(tickets[0]), p1(tickets[1]), p2(tickets[2]), p3(tickets[3]);
    try {
      Allocator<ControlContext> base_allocator(tickets[2]);
      auto *raw = base_allocator.allocate(1);
      try { base_allocator.construct(raw, tickets[2]); }
      catch (...) { base_allocator.deallocate(raw, 1); throw; }
      context = raw; // Only now is there a readable, constructed owner.
      Allocator<WGCScreenPlatformContext> platform_allocator(tickets[3]);
      auto *platform = platform_allocator.allocate(1);
      try { platform_allocator.construct(platform); }
      catch (...) { platform_allocator.deallocate(platform, 1); throw; }
      platform->storage_ticket = tickets[3];
      platform->parent_ctx = &context->value;
      context->value.platform_ctx = platform;
      result = miniav_wgc_strict_create_funded(&context->value, platform, nullptr,
          tickets[0], tickets[1], &platform->strict_holder);
      if (result != MINIAV_SUCCESS) throw BuildFailure{result};
      out->disposition = 2; // Actual cold owner; no source was started.
      out->context_value = reinterpret_cast<uintptr_t>(&context->value);
      return MINIAV_SUCCESS;
    } catch (const BuildFailure &failure) { result = failure.result; }
    catch (const std::bad_alloc &) { result = MINIAV_ERROR_OUT_OF_MEMORY; }
    catch (Error error) {
      result = error == Error::Refused ? MINIAV_ERROR_INVALID_OPERATION : MINIAV_ERROR_SYSTEM_CALL_FAILED;
    }
    catch (...) { result = MINIAV_ERROR_SYSTEM_CALL_FAILED; }
    if (context && release_storage(context) != MINIAV_SUCCESS) {
      out->disposition = 3;
      out->context_value = reinterpret_cast<uintptr_t>(&context->value);
      return result;
    }
  } // All unallocated roles cancelled before the cold closure acknowledgement.
  if (tickets[2].notify(Event::ColdScopeClosed)) out->disposition = 1;
  else {
    tickets[2].quarantine();
    out->disposition = 4;
  }
  return result;
}

MiniAVResultCode miniav_wgc_strict_control_release(MiniAVScreenContext *base) {
  if (!base || base->strict_control_owner != base) return MINIAV_ERROR_INVALID_ARG;
  auto *context = static_cast<ControlContext *>(base->strict_control_owner);
  Ticket scope = context->ticket;
  const auto result = release_storage(context);
  if (result == MINIAV_SUCCESS && !scope.notify(Event::ColdScopeClosed)) scope.quarantine();
  return result;
}
