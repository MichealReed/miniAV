// Deterministic WGC payload ownership and immutable-import provenance gate.
// No capture session, GPU device, window or COM apartment is required.
// --inject-extra-ref restores the original redundant AddRef and must fail.
#include "../windows/wgc_frame_texture.h"
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <vector>

struct Counts {
  unsigned created = 0;
  unsigned destroyed = 0;
};

struct CountedTexture : IUnknown {
  explicit CountedTexture(Counts& counts) : counts_(counts) { ++counts_.created; }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID, void** out) override {
    if (out) *out = nullptr;
    return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override {
    const auto remaining = --refs_;
    if (!remaining) {
      ++counts_.destroyed;
      delete this;
    }
    return remaining;
  }
 private:
  Counts& counts_;
  ULONG refs_ = 1;
};

int main(int argc, char** argv) {
  const bool inject = argc > 1 && !std::strcmp(argv[1], "--inject-extra-ref");
  Counts counts;
  std::vector<IUnknown*> pending;
  constexpr unsigned frames = 10000;
  for (unsigned i = 0; i < frames; ++i) {
    winrt::com_ptr<IUnknown> source;
    source.attach(new CountedTexture(counts));
    try {
      auto retained = wgc_retain_frame_texture(source);
      if (inject) retained->AddRef(); // original WGC bug, positive control
      // Payload allocation failures rely on com_ptr cleanup before detach.
      if (i % 7 == 0) throw std::runtime_error("payload allocation failed");
      auto* payload = retained.detach();
      // Busy captures release immediately; consumers may hold several leases.
      if (i % 3 == 0) payload->Release();
      else pending.push_back(payload);
    } catch (const std::runtime_error&) {
    }
    if (pending.size() == 4) {
      pending.front()->Release();
      pending.erase(pending.begin());
    }
  }
  for (auto* payload : pending) payload->Release();
  const bool balanced = counts.created == counts.destroyed;
  const bool tags =
      wgc_frame_import_tag(true, S_OK) == MINIAV_D3D11_IMMUTABLE_READY_TAG &&
      wgc_frame_import_tag(false, S_OK) == 0 &&
      wgc_frame_import_tag(true, S_FALSE) == 0 &&
      wgc_frame_import_tag(true, E_FAIL) == 0 &&
      wgc_frame_import_tag(false, E_FAIL) == 0;
  std::printf("created=%u destroyed=%u outstanding=%u tags=%s injected=%s\n",
      counts.created, counts.destroyed, counts.created - counts.destroyed,
      tags ? "pass" : "FAIL", inject ? "true" : "false");
  return balanced && tags ? 0 : 1;
}
