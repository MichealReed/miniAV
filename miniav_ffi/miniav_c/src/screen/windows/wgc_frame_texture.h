#pragma once

#include "../../../include/miniav_buffer.h"
#include <windows.h>
#include <unknwn.h>
#include <winrt/base.h>

// Hold one reference while the frame's payload is prepared. detach() later
// transfers this exact reference to wgc_release_buffer. A com_ptr copy already
// calls AddRef; adding another reference here leaks one texture per frame.
template <typename Texture>
winrt::com_ptr<Texture> wgc_retain_frame_texture(
    const winrt::com_ptr<Texture>& texture) noexcept {
  return texture;
}

// A fresh snapshot cannot be overwritten by WGC's capture pool. S_OK is the
// positive completion proof; S_FALSE, failed queries and timeout are untagged.
inline uint64_t wgc_frame_import_tag(bool private_copy,
                                     HRESULT completion) noexcept {
  return private_copy && completion == S_OK
             ? MINIAV_D3D11_IMMUTABLE_READY_TAG
             : 0;
}
