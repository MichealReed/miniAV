// Included in the genuine production-type storage witness translation unit.
namespace {
MiniAVWindowsStrictControlStorageAuthorityV1 descriptor(Fixture &f) {
  MiniAVWindowsStrictControlStorageAuthorityV1 value{};
  value.struct_size = sizeof(value); value.abi_version = 1;
  value.context = &f; value.ops = &ops;
  value.generation = f.generation; value.source_epoch = f.source_epoch;
  value.role_count = 4;
  for (size_t i = 0; i < 4; ++i)
    value.roles[i] = {f.slots[i].extent.bytes, f.slots[i].extent.alignment, 0};
  return value;
}
MiniAVWindowsStrictControlStorageOutcomeV1 output() {
  MiniAVWindowsStrictControlStorageOutcomeV1 value{};
  value.struct_size = sizeof(value); value.abi_version = 1;
  return value;
}
void unsupported_control_case() {
  MiniAVWindowsStrictControlStorageProfileV1 profile{};
  profile.struct_size = sizeof(profile); profile.abi_version = 1;
  auto result = output();
  begin();
  require(MiniAV_Screen_Windows_GetStrictControlStorageProfileV1(&profile) == MINIAV_ERROR_NOT_SUPPORTED &&
      !profile.struct_size, "unsupported control profile");
  require(MiniAV_Screen_Windows_CreateFundedControlV1(nullptr, &result) == MINIAV_ERROR_NOT_SUPPORTED &&
      result.disposition == 0 && !result.context_value && result.result == MINIAV_ERROR_NOT_SUPPORTED,
      "unsupported whole control factory");
  end(); require(heap_count == 0, "unsupported bootstrap before all heaps");
}
void control_cases() {
  MiniAVWindowsStrictControlStorageProfileV1 p{};
  p.struct_size = sizeof(p); p.abi_version = 1;
  require(MiniAV_Screen_Windows_GetStrictControlStorageProfileV1(&p) == 0 &&
      p.struct_size == 176 && p.flags == 3 && p.role_count == 4 && p.additional_resources == 2,
      "real full cold profile");
  uint64_t total = 0;
  for (uint32_t i = 0; i < 4; ++i) { require(p.roles[i].kind == i, "four canonical roles"); total += p.roles[i].requested_bytes; }
  require(total == p.total_requested_bytes, "actual four-role price");
  static Fixture exact, wrong, failures[4], before[3], after, create_retained, create_unknown;
  struct ExtendedProfile { MiniAVWindowsStrictControlStorageProfileV1 prefix; uint64_t suffix; } extended{p, 0x12345678};
  extended.prefix.struct_size = sizeof(extended);
  require(MiniAV_Screen_Windows_GetStrictControlStorageProfileV1(&extended.prefix) == 0 &&
      extended.suffix == 0x12345678, "full profile preserves unknown suffix");
  uint32_t short_out[2]{8, 1};
  require(MiniAV_Screen_Windows_CreateFundedControlV1(nullptr,
      reinterpret_cast<MiniAVWindowsStrictControlStorageOutcomeV1 *>(short_out)) == MINIAV_ERROR_INVALID_ARG &&
      short_out[0] == 8 && short_out[1] == 1, "short constructor output untouched");
  exact.init(p); auto a = descriptor(exact); auto out = output();
  begin();
  require(MiniAV_Screen_Windows_CreateFundedControlV1(&a, &out) == 0 &&
      out.result == 0 && out.disposition == 2 && out.context_value &&
      out.generation == a.generation && out.source_epoch == a.source_epoch && out.flags == 1,
      "funded four-role cold create outcome");
  require(heap_count == 4 && allocation(0, exact, 2) && allocation(1, exact, 3) &&
      allocation(2, exact, 1) && allocation(3, exact, 0), "four exact actual allocations");
  auto *base = reinterpret_cast<MiniAVScreenContext *>(out.context_value);
  auto *platform = static_cast<WGCScreenPlatformContext *>(base->platform_ctx);
  require(base->strict_control_owner == base && !base->ops && !base->is_running &&
      !base->is_configured && !platform->ctx_magic && !platform->d3d_device &&
      !platform->stop_event_handle && !platform->frame_pool &&
      !platform->callbacks_in_flight.load() && !platform->is_streaming.load(), "no activation in cold context");
  auto alias = get(platform->strict_holder);
  auto weak = std::weak_ptr<Owner>(alias);
  require(MiniAV_Screen_Windows_ReleaseFundedControlV1(base) == 0 && heap_count == 7 &&
      freed(4, exact, 0) && freed(5, exact, 3) && freed(6, exact, 2) && exact.terminal,
      "actual context/platform/holder consumption and no-source closure");
  alias.reset(); require(weak.expired() && heap_count == 7 && exact.cpu == total,
      "weak owner tail retains four-role debt after cold closure");
  weak.reset(); end();
  require(heap_count == 8 && freed(7, exact, 1) && !exact.cpu && !exact.references,
      "genuine weak-tail free settles cold cohort");

  wrong.init(p); auto bad = descriptor(wrong); ++bad.roles[3].requested_bytes;
  out = output(); begin();
  require(MiniAV_Screen_Windows_CreateFundedControlV1(&bad, &out) == MINIAV_ERROR_INVALID_ARG &&
      out.disposition == 0 && !out.context_value && !wrong.references,
      "complete quote validates before first retain/allocation");
  end(); require(!heap_count, "bad full quote zero allocations");
  for (int failed = 1; failed <= 4; ++failed) {
    auto &f = failures[failed - 1]; f.init(p); a = descriptor(f); out = output();
    begin(); fail_allocation = failed;
    const auto status = MiniAV_Screen_Windows_CreateFundedControlV1(&a, &out);
    end(); fail_allocation = 0;
    require(status == MINIAV_ERROR_OUT_OF_MEMORY && out.result == status && out.disposition == 1 &&
        !out.context_value && !f.cpu && !f.references && f.terminal && !f.quarantined,
        "every real allocation failure closes only after actual rollback/cancels");
    require(heap_count == static_cast<size_t>(2 * failed - 1), "exact rollback allocation/free count");
  }
  for (uint32_t role : {0u, 3u, 2u}) {
    auto &f = before[role == 0 ? 0 : role == 3 ? 1 : 2]; f.init(p);
    a = descriptor(f); out = output();
    require(MiniAV_Screen_Windows_CreateFundedControlV1(&a, &out) == 0, "cold pre-free fault create");
    base = reinterpret_cast<MiniAVScreenContext *>(out.context_value);
    f.refusal_role = role; f.refuse_before_free = true;
    begin();
    require(MiniAV_Screen_Windows_ReleaseFundedControlV1(base) == MINIAV_ERROR_SYSTEM_CALL_FAILED &&
        base->strict_control_owner == base && f.quarantined && f.cpu == total && f.references > 0,
        "prefree refusal preserves readable context and original debt");
    end();
    require(heap_count == (role == 0 ? 0 : role == 3 ? 2 : 3), "consumed children not retried or resurrected");
  }
  create_retained.init(p); create_retained.refuse_before_free = true; create_retained.refusal_role = 3;
  a = descriptor(create_retained); out = output();
  begin(); fail_allocation = 3; // Real Owner allocation fails, platform cleanup refuses.
  const auto retained_result = MiniAV_Screen_Windows_CreateFundedControlV1(&a, &out);
  end(); fail_allocation = 0;
  base = reinterpret_cast<MiniAVScreenContext *>(out.context_value);
  require(retained_result == MINIAV_ERROR_OUT_OF_MEMORY && out.result == retained_result &&
      out.disposition == 3 && base && base->strict_control_owner == base && base->platform_ctx &&
      heap_count == 3 && create_retained.quarantined && create_retained.cpu == total && create_retained.references > 0,
      "constructor failure returns a genuinely retained readable context on uncertain cleanup");

  create_unknown.init(p); create_unknown.refuse_allocated = true; create_unknown.refusal_role = 2;
  a = descriptor(create_unknown); out = output(); begin();
  require(MiniAV_Screen_Windows_CreateFundedControlV1(&a, &out) == MINIAV_ERROR_SYSTEM_CALL_FAILED &&
      out.disposition == 4 && !out.context_value && create_unknown.quarantined &&
      create_unknown.cpu == total && create_unknown.references > 0,
      "lost first-address receipt is quarantined without inventing a readable handle");
  end(); require(heap_count == 1 && heap_events[0].kind == 1, "unknown actual first heap retained");
  after.init(p); a = descriptor(after); out = output();
  require(MiniAV_Screen_Windows_CreateFundedControlV1(&a, &out) == 0, "cold final receipt fault create");
  after.refusal_role = 2; after.refuse_after_free = true;
  begin();
  require(MiniAV_Screen_Windows_ReleaseFundedControlV1(
      reinterpret_cast<MiniAVScreenContext *>(out.context_value)) == 0,
      "final actual context free is committed consumption despite receipt fault");
  end();
  require(heap_count == 4 && after.quarantined && after.cpu == total && after.references > 0,
      "consumed pointer never retryable; uncertain authority retained");
  std::printf("PASS cold native bootstrap: holder=%llu owner=%llu base=%llu platform=%llu total=%llu added_resources=2\n",
      static_cast<unsigned long long>(p.roles[0].requested_bytes),
      static_cast<unsigned long long>(p.roles[1].requested_bytes),
      static_cast<unsigned long long>(p.roles[2].requested_bytes),
      static_cast<unsigned long long>(p.roles[3].requested_bytes),
      static_cast<unsigned long long>(total));
}
}
