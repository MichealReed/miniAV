/// Opus bitstream helpers — pure Dart, web-safe (no FFI, no dart:io).
///
/// Shared by the native and WASM encoders (OpusHead) and by the Ogg demuxer
/// (packet duration from the TOC byte).
library;

import 'dart:typed_data';

/// 'OpusHead' magic (RFC 7845 §5.1).
const List<int> opusHeadMagic = [0x4F, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64];

/// Build a minimal OpusHead (RFC 7845 §5.1): magic + version + channels +
/// pre-skip + input rate + output gain + mapping family 0.
///
/// [preSkip48k] is the encoder's lookahead expressed at 48 kHz — the unit the
/// field is defined in, regardless of [inputSampleRate]. It is what tells a
/// decoder how many priming samples to throw away; a hard-coded 0 leaves the
/// encoder delay in the file.
Uint8List buildOpusHead(int channels, int inputSampleRate, int preSkip48k) {
  final b = Uint8List(19);
  final bd = ByteData.sublistView(b);
  b.setRange(0, 8, opusHeadMagic);
  b[8] = 1; // version
  b[9] = channels;
  bd.setUint16(10, preSkip48k & 0xFFFF, Endian.little); // pre-skip
  bd.setUint32(12, inputSampleRate, Endian.little);
  bd.setUint16(16, 0, Endian.little); // output gain
  b[18] = 0; // channel mapping family 0 (mono/stereo)
  return b;
}

/// Read the pre-skip (48 kHz samples) out of an OpusHead, or 0 if [head] is not
/// one / is too short.
int opusHeadPreSkip(List<int> head) {
  if (head.length < 12) return 0;
  for (var i = 0; i < 8; i++) {
    if (head[i] != opusHeadMagic[i]) return 0;
  }
  return head[10] | (head[11] << 8);
}

/// Samples-at-48 kHz per FRAME for each of the 32 TOC configurations
/// (RFC 6716 §3.1): SILK 10/20/40/60 ms at NB/MB/WB, hybrid 10/20 ms at
/// SWB/FB, CELT 2.5/5/10/20 ms at NB/WB/SWB/FB.
const List<int> _configSamples48k = [
  480, 960, 1920, 2880, // 0-3   SILK NB  10/20/40/60 ms
  480, 960, 1920, 2880, // 4-7   SILK MB
  480, 960, 1920, 2880, // 8-11  SILK WB
  480, 960, //             12-13 Hybrid SWB 10/20 ms
  480, 960, //             14-15 Hybrid FB
  120, 240, 480, 960, //   16-19 CELT NB  2.5/5/10/20 ms
  120, 240, 480, 960, //   20-23 CELT WB
  120, 240, 480, 960, //   24-27 CELT SWB
  120, 240, 480, 960, //   28-31 CELT FB
];

/// Duration of one Opus packet in 48 kHz samples, from its TOC byte
/// (RFC 6716 §3.1), or 0 if the packet is empty/malformed.
///
/// 20 ms is only the DEFAULT frame size — 2.5/5/10/40/60 ms packets are legal
/// and common (WebRTC senders use 10 ms, low-bitrate speech uses 40/60), and a
/// packet may pack up to 48 frames. Assuming 20 ms is wrong by up to 8x in
/// either direction.
int opusPacketSamples48k(List<int> packet) {
  if (packet.isEmpty) return 0;
  final toc = packet[0];
  final perFrame = _configSamples48k[(toc >> 3) & 0x1F];
  final code = toc & 0x03;
  final int frames;
  switch (code) {
    case 0:
      frames = 1;
    case 1:
    case 2:
      frames = 2;
    default: // code 3: frame count in the low 6 bits of the next byte
      if (packet.length < 2) return 0;
      frames = packet[1] & 0x3F;
  }
  if (frames < 1 || frames > 48) return 0;
  final total = perFrame * frames;
  // RFC 6716 §3.1: a packet may not exceed 120 ms of audio.
  return total > 5760 ? 0 : total;
}
