# Changelog

## 0.7.7

- Raise the spawn constraint to ^0.1.1 — native transfer now actually transfers, and a web message the worker cannot deserialize is reported instead of vanishing.

## 0.7.6

- The MP4 writer accepts a video track whose encoder has not published its configuration record yet. It builds `moov` at `finish()` and `stsd` with it, so the record is not needed until then - but `open` refused without one, and a recorder builds its muxer before a single frame has been encoded. A hardware H.264 MFT is allowed to withhold its sequence header until it has produced output (Intel Quick Sync does; NVIDIA does not), so on those machines the whole recording fell back to FFmpeg - whose file output carries `+faststart`, which rewrites the entire file at `av_write_trailer`. `setTrackConfig` now supplies the record and settles Annex-B framing with it; output is byte-identical to supplying it at open.

- New `Mp4Muxer.tracksMissingConfig`: a track whose record never arrived is reported rather than thrown. Its samples are all in the file and its sample entry is missing, so it will not decode - and refusing to write `moov` over it would take every working track down with it.

## 0.7.5

- Increment downstream deps
- Increment downstream deps
- Increment downstream deps

## 0.7.4

- MP4: a decode timestamp that steps backwards is now REPAIRED rather than refused. finish() used to throw over media that was already fully written, leaving ftyp+mdat with no moov - a container no player opens - so one reordered packet early in a session destroyed the whole recording. Out-of-order packets are now counted as they arrive, naming the track and the sample so a bad session is knowable while it still runs, and clamped forward by the smallest amount that makes the sample table legal when the index is built; Mp4Muxer.timingReports reports both. Recordings with no reordering are byte-identical to before. finish() also no longer leaks the file handle when the index cannot be built.

- MP4: a track's codec configuration record can now change part-way through a recording, via Mp4Muxer.setTrackConfig - for an encoder reopened after a graphics device reset, which issues its own parameter sets. Identical records are a no-op; different ones get a second stsd sample entry with the later chunks pointing at it, rather than samples being written under a record that does not describe them.

- Media Foundation: a shared-handle import failure now tells an encoder on a different adapter (nothing ever imported) apart from a capture that died (frames imported, then stopped), instead of always blaming the adapter.

- `AudioRingSink.open` now verifies `destination.maxChannelCount` can carry
  the requested channel count and declines otherwise, so a surround request
  on stereo-capped hardware falls back cleanly instead of being silently
  down-mixed (or per-browser, dropped).

- For channel counts above 2 the sink addresses the destination discretely
  (`channelInterpretation: 'discrete'`, explicit channel counts on the node
  chain) so a finished multichannel speaker feed is not run through the Web
  Audio up/down-mix matrix.

## 0.7.3

- Fix wasm codec loading inside Web Workers: the loader now detects worker scope and uses importScripts with a glue URL resolved from the worker script location instead of assuming a DOM document. Wasm codecs previously fell back silently to WebCodecs in workers.

## 0.7.2

- Web audio can now play entirely off the main thread: an AudioWorklet reads decoded PCM from shared memory that a worker fills, so a busy main thread no longer starves playback. Fixes two WebCodecs decoder faults: a packet handed to decode() was dropped whenever a frame was already buffered, which broke the reference chain for every frame after it, and both decoders passed the whole backing buffer instead of the packet's view of it. Decoders now wait on the output callback instead of polling a timer the browser clamps to 4ms, taking audio decode from 5.0ms to 0.1ms per packet. Worker-hosted demux and decode are available behind backendOptions['worker'] = 'true'. Also exposes the Media Foundation encoder's bound D3D11 device, and decodes AAC in the decodeAudioData fallback by synthesizing ADTS headers so browsers without WebCodecs audio can play it.

## 0.7.1

- released 08/13/26 - MR

## 0.7.0

- **`MfVideoEncoder.flush()` raises instead of returning an empty list when the
  drain did not finish, or when the session produced nothing at all.** Two
  genuinely silent failures are now typed `CodecRuntimeException`s: a drain that
  never reaches `METransformDrainComplete` (previously the 2 s poll expired and
  the truncated tail was returned as if complete), and a session that ACCEPTED
  frames yet emitted zero packets across its whole life (a video track with no
  video, reported as success at every step). The flush deadline is also now
  measured from the last packet handed back rather than from the start of the
  flush: every poll is marshalled to the one process-wide MTA worker, so several
  concurrent sessions can stretch a healthy drain past any absolute budget —
  "no output at all for 2 s" is the condition that means wedged.
  Trap: `flush()` returning empty is NOT by itself evidence of lost output.
  `encode()` returns a packet whenever the async MFT raised
  `METransformHaveOutput` while that call was in flight, so which of the two
  delivers a given frame is load-dependent — measured on one box, a single
  frame's whole 2847 B keyframe came back from `encode()` with `flush()` empty
  and the drain complete. Callers must SUM both halves; `mf_frame_sources_test`
  counted only `flush()` and failed on roughly half of default-concurrency runs
  as a result (0 of 12 after; 8 of 8 fail when the accounting is reverted).

- New (test-only): `mfencSetFault(handle, mode)` /
  `miniav_shim_mfenc_set_fault` — make ONE encoder session behave like a broken
  MFT, so the two `flush()` failures above can be reached without one. Mode 1
  makes the drain never report complete (`mfencDrainState` keeps answering 0);
  mode 2 accepts input, yields no packets from `mfencReceive`, and reports the
  drain COMPLETE — that last part is what separates "wedged" from "produced no
  video at all". Mode 0 (every session's default) is inert, and an unknown mode
  returns -1 rather than arming anything. Covered by
  `mf_encoder_flush_faults_test.dart`, which fails if either throw is removed.
  Trap: the mode is a field on the SESSION, never a global or an environment
  variable. `dart test` runs each test file in its own isolate inside one
  process, and these sessions share that process and its single MTA worker, so a
  process-wide switch injects the fault into whatever else is encoding at the
  time. Mode 1 also yield-spins ~1 ms per poll on purpose: returning instantly
  would turn the caller's timeout loop into a marshal storm holding that
  worker's gate against every other session.

- **libopus is built thread-safe on Windows (`USE_ALLOCA`), not with its
  process-global pseudostack.** `native/cmake/opus.cmake` gave every MSVC build
  `NONTHREADSAFE_PSEUDOSTACK` — libopus's last-resort mode, in which all of its
  per-call scratch arrays come out of ONE process-global 120 000-byte buffer
  behind an unsynchronised bump pointer. Two threads inside libopus at the same
  time therefore get handed the SAME scratch bytes and lose each other's updates
  to the pointer, so it walks off the end of the buffer and libopus memcpys over
  the heap. Windows now uses `USE_ALLOCA` (per-call, on the calling thread's own
  stack — what upstream's CMake picks for MSVC); other toolchains keep
  `VAR_ARRAYS`. Measured with an 8-thread harness under clang-cl ASan: `WRITE of
  size 4096 … 320 bytes after 120000-byte region allocated by
  opus_alloc_scratch`, from `run_prefilter` in `celt_encoder.c`, 10 runs out of
  10 — and 0 out of 10 with `USE_ALLOCA`. `dart test` (default concurrency,
  597 tests) then went from aborting to 0 aborts in 10 runs, and restoring the
  one cmake define brings the abort back.
  New: `miniav_opus_scratch_mode()` (native) / `opusScratchMode()` (Dart) return
  the compiled mode, and `opus_encode_test.dart` fails on
  `NONTHREADSAFE_PSEUDOSTACK` so a build-config regression is caught as a test
  failure instead of as a corrupted process.
  Trap: this NEVER faults at the culprit. Any decode/encode on any thread can be
  the one that scribbles; the process dies later wherever it next touches the
  damaged heap, with a different fault code each run (`0xC0000005`,
  `0xC0000374`, `0xC0000094`, `0xC0000409`) and a stack pointing at whichever
  code was unlucky. Two earlier investigations blamed two unrelated subsystems
  by reading those stacks. Reach for a heap tool, not the crash site.
- **The Opus encoder writes libopus's real lookahead as the OpusHead pre-skip.**
  It hard-coded 0, so every file we produced began with the encoder's priming
  as audible audio and ran ~6.5 ms ahead of video in VLC/Chrome/ffplay. The
  value now comes from `OPUS_GET_LOOKAHEAD` through a new
  `miniav_opus_enc_lookahead` native export (also in the WASM module), scaled to
  48 kHz — the unit RFC 7845 defines the field in, so at 24 kHz the header value
  is unchanged while libopus reports half as many samples. The MP4 `dOps` and
  Ogg paths already carried whatever the header said. Trap: a round-trip through
  our own decoder cannot see this, because the decoder honours whatever pre-skip
  it reads; the test asserts against the encoder's reported lookahead and
  cross-correlates decoded output against the input.
- **WAV demux reads `WAVE_FORMAT_EXTENSIBLE`, 24-bit and 8-bit PCM.** Only fmt 1
  16-bit and fmt 3 f32 were accepted, which rejects most multichannel/24-bit
  files, since anything past 2 channels or 16 bits is written as EXTENSIBLE
  (0xFFFE). The SubFormat GUID now decides the format and `wValidBitsPerSample`
  is honoured (0 means "the whole container"; anything narrower is refused
  rather than mis-scaled). Because the platform interface has two PCM codecs,
  the DEMUXER converts: 8-bit unsigned → `pcmS16le` (`(b-128) << 8`), 24-bit
  packed → `pcmF32le` (`v / 2^23`) — both exact. The track's codec therefore
  describes the emitted packets, not the bits on disk. 32-bit integer and
  64-bit float still fall through to FFmpeg.
- **The container sniffer requires the RIFF form type to be `WAVE`.** Any RIFF
  magic was answered `Container.wav`, so `.avi` (and WebP/ANI/RMID) went to the
  WAV parser — a wasted fall-through on the VM and a hard failure on web, where
  there is no second demuxer. `ContainerFramingBackend.sniff` is now public so
  the decision is testable: a wrong guess and a right one both end in a null
  demuxer, which makes them indistinguishable from outside.
- **Ogg/Opus timing comes from the packet TOC and page granule positions.**
  Duration was `packetCount * 20000`, per-packet PTS was `index * 20000`, and
  `seek` divided by the same constant — but 10/40/60 ms packets are legal and
  common, so all three were off by up to 3x. Duration is now the final granule
  minus the pre-skip (which is also what accounts for tail trimming), PTS and
  packet duration come from each packet's TOC byte, and `seek` binary-searches
  the resulting timeline. `OggMuxer` writes granule positions from the TOC too
  instead of assuming 960 samples per page. Packet durations sit on the same
  pre-skipped timeline as the PTS — each packet ends where the next begins, so
  the durations add up to `durationUs`; charging packet 0 its full TOC length
  while its start had been pulled back put a remuxer's sample table (MP4 `stts`
  is built from `EncodedPacket.durationUs`) at odds with the PTS it was handed.
- **`Mp4Demuxer.durationUs` includes the last sample's own duration.** It
  returned `max(pts)`, so every file read back one sample short and a
  single-sample track reported 0 µs.
- **`AdtsDemuxer.durationUs` is no longer null.** It is computed by a frame walk
  (header hops only, no payload touched) on first read and cached, so a plain
  `.aac` finally shows a seek bar. The walk reuses the normal framing path, so
  tags and corruption are priced exactly as playback prices them, and it saves
  and restores the read cursor. Like every other demuxer's, the getter stays
  readable after `close()`: a player reads `duration` unguarded and does not
  null its demuxer, so throwing there fires during an ordinary teardown.
- **`WavMuxer` and `AdtsMuxer` stream to a `FileMuxerOutput`.** Both buffered
  the entire recording in RAM and only wrote at `finish()`. WAV now writes its
  44-byte header up front and patches the two RIFF lengths at the end (new
  `MuxerFileSink.patchU32Le`); ADTS just appends, since it has no length field
  anywhere. Both expose `ownsFileOutput`, and the backend stops wrapping them in
  the collect-then-save adapter; `getBytes()` returns null in streaming mode
  because nothing is retained. Bytes-output behaviour is byte-for-byte
  unchanged, including after `close()` — it auto-finishes and `getBytes()` has
  no ordering guard, so neither writer drops its buffer there. Trap: an
  interrupted streaming recording is a file whose two RIFF lengths were never
  patched, so `WavDemuxer` reads a 0-length `data` chunk as running to EOF (it
  used to return zero packets, and since `open()` still succeeded the negotiator
  never fell through to a demuxer that could recover the audio).
  `OggMuxer` deliberately still buffers: a page carries a CRC over
  its own bytes plus a granule position and sequence number, so streaming it
  means a page-packing policy, and nothing here records into Ogg open-endedly.
- **The Media Foundation video decoder now crops to the display aperture.** It
  reported the macroblock/CTU-padded CODED size (240 arrived as 256, 1080 as
  1088) and the mapped buffer carried those padding rows as picture. The
  negotiated output type's `MF_MT_MINIMUM_DISPLAY_APERTURE` (then
  `MF_MT_GEOMETRIC_APERTURE`) is now honoured at open and on every
  stream-change renegotiation; frames report the display size and
  `readBytes()` returns exactly `width * height * 3 / 2`. An absent aperture
  still means no crop, so block-aligned streams are unchanged. The D3D11
  texture stays coded-size with the valid region at the top-left — import it
  with the frame's `width`/`height`, not the texture's.
- **`SwAudioDecoder` no longer withholds MP3 audio until `flush()`.** It buffers
  because the native entry points take a complete buffer, but returning nothing
  from every `decode()` starves a streaming consumer: a player wrote no audio
  for the whole file and then received the entire track as one chunk during its
  end-of-stream drain, which plays a fraction of a second and reports EOS. Fed
  more than one packet it now decodes in ~16 KiB batches and emits as it goes,
  timestamped from each batch's first packet instead of 0. A whole-file feed
  (one packet, then flush) is unchanged. Trap: a batch is decoded with the
  previous batch's tail in front of it and trimmed back by
  `mp3PcmFrameCount`, because a cold `drmp3_init_memory` spends the first frame
  syncing — without that, every batch dropped a frame (~1 s lost per 30 s).
  Pinned by a test asserting batched output is sample-identical to a whole-file
  decode. Batching is MP3-only: an MP3 batch is a run of self-contained frames,
  while a FLAC or Ogg-Vorbis batch is a slice of a CONTAINER that
  `drflac_open_memory` / `stb_vorbis_open_memory` reject, so a whole-file feed
  of either still accumulates and decodes once at `flush()` however many chunks
  it arrives in.
- **`SwAudioBackend` no longer claims FLAC or Vorbis decode; they route to
  FFmpeg.** `SwAudioDecoder` ignores `AudioDecoderConfig.extraData`, which is
  where a demuxer puts the FLAC STREAMINFO / Vorbis setup headers it strips, and
  the native entry points (`drflac_open_memory` / `stb_vorbis_open_memory`) need
  a whole container — so a demuxed stream threw `CodecRuntimeException` on every
  batch. Streamed FLAC/Vorbis through this backend had therefore never worked.
  Trap: the claim was not merely optimistic, it was terminal — priority 55
  outranks FFmpeg and `SwAudioDecoder.open` can never return `null`, so winning
  the negotiation left nothing to fall through to. Whole-file feeds through
  `SwAudioDecoder` directly still decode all three codecs; reclaiming the codecs
  for negotiation needs header synthesis from `extraData` first.
- **`Mp4Demuxer.seek` lands on a VIDEO keyframe at/before the target.** It
  scanned every track — audio has no `stss`, so all its samples are flagged as
  sync points and an interleaved file always seeked into the middle of a video
  GOP. Trap: the scan also stopped at the first sample with `ptsUs > target`
  while the sample list is in FILE-OFFSET order, so B-frame reordering
  terminated it early. Audio-only files keep the any-track rule.
- **ADTS demux survives ID3 tags and corruption.** `AdtsDemuxer.open` now skips
  leading ID3v2 tags, matching the sniffer, which had accepted a tagged `.aac`
  the parser then rejected (fatal on web, where there is no fallback demuxer).
  `readPacket` treats an ID3v1 `TAG` trailer / trailing ID3v2 as a clean end and
  resyncs forward past bad headers (double-confirmed, as in `Mp3Demuxer`) rather
  than returning EOF at the first one — one corrupt frame used to truncate the
  rest of the file silently. A resync also charges the skipped span to the frame
  counter: PTS is derived from the number of frames emitted, so hunting past
  damage without pricing it stamped every remaining packet early by the lost
  frames' duration, permanently (a 5-frame burst at 44.1 kHz runs the rest of
  the file ~116 ms ahead of the video). `seek` stops on the frame a resync lands
  on instead of consuming it. `channel_configuration` 7 now maps to 8 channels
  on both read and write (it is an enum, not a count); configuration 0 stays
  rejected.
- **The MF decoder harvests the HEVC frame size from the SPS, and declines when
  there is none.** The HEVC decoder MFT requires `MF_MT_FRAME_SIZE` on its input
  type and rejects every `ProcessInput` without it — but the session still
  creates successfully, so the negotiator committed to a decoder that accepted
  packets and produced nothing (a black screen, no error). When
  `DecoderConfig.width`/`height` are unset, `MfD3d11Decoder.open` now reads
  `pic_width/height_in_luma_samples` out of the parameter sets in
  `extraData` — an `hvcC` record or a raw Annex-B sequence header — and hardware
  decode proceeds; with neither dims nor a parsable SPS — or one whose dimensions
  exceed what any HEVC level allows — it returns `null` and
  negotiation falls to the software decoder. H.264 is unaffected throughout: its
  MFT parses dimensions in-band. Trap: the harvested size is the CODED size, not
  the display size — the input type describes the CTU grid (1080 codes as 1088),
  and the output's display aperture still governs what a frame reports. Trap: the
  size is bounded before use, not just checked for `> 0` — the native side takes
  it as `Int32` and an out-of-range SPS value would truncate to a negative there,
  silently dropping `MF_MT_FRAME_SIZE` and reinstating the never-emits decoder.
- **`Mp4Muxer` writes the `tkhd` display matrix for
  `VideoTrackInfo.rotationDegrees`.** It always wrote the unity matrix, so a
  portrait recording round-tripped through this muxer came back as rotation 0
  and played sideways; `Mp4Demuxer` had read the matrix all along. 0/90/180/270
  map to the same (a,b,c,d) values ffmpeg's `-display_rotation` writes (degrees
  CLOCKWISE); anything else writes unity rather than a transform the reader
  would report as 0. `tkhd` width/height stay the coded size — the matrix alone
  declares the orientation, and swapping them too rotates the picture twice.
- Every entry of both MP3 bitrate tables and all three sample rates of each
  MPEG version are now pinned by an exhaustive header-matrix test (252
  combinations of version x bitrate index x rate index x padding, checked
  against hand-transcribed ISO constants); the 0.6.9 fixtures only ever
  exercised sample-rate index 0.

## 0.6.9

### Media Foundation video encoder

- **`flush()` no longer wedges the session or drops the tail.** A drain is now
  tracked as its own state and ended by `METransformDrainComplete`; the next
  submit re-sends `MFT_MESSAGE_NOTIFY_START_OF_STREAM` and forgets the stale
  pre-drain input credit, so `flush()` followed by `encode()` keeps encoding.
  New `mfencDrainState` lets `flush()` wait for the drain to actually complete
  rather than stopping at the first "nothing right now" — an async hardware MFT
  answers that long before it has handed back the frames it still holds.
- **New `MfVideoEncoder.invalidateImports()`.** The D3D11 import cache keys on
  the producer's texture pointer; it now holds a reference to that texture, so
  a freed-and-recycled address can no longer resolve to the previous picture
  (the frozen-frame failure). The cost is that the producer's texture stays
  resident until the entry is evicted — call `invalidateImports()` on a
  resolution change or a rebuilt texture ring to release it.
- CPU NV12/I420 input accepts odd dimensions: stride is `(w+1)&~1` with
  `(h+1)>>1` chroma rows on both sides, the last column and missing chroma row
  are replicated, and the media type keeps the real WxH.
- Texture import failures and back-pressure are now distinct: every native
  failure path records why (staging exhaustion, `VideoProcessorBlt`,
  `MFCreateDXGISurfaceBuffer`, both `ProcessInput` shapes, the shared-handle
  open), and a full input queue no longer reports itself as "could not open the
  capture texture".
- `MfVideoEncoder` is `Finalizable` (native session + frame struct), and every
  native read throws `StateError` after `close()` instead of using a freed
  handle.

### ISO-BMFF muxer / demuxer

- **B-frame timestamps are correct.** `stts` deltas derive from DTS and a
  `ctts` box is written whenever any packet has `ptsUs != dtsUs`, with the
  version-0 non-negative shift undone by the edit list. Strictly decreasing DTS
  now throws instead of producing a garbage file.
- 64-bit where required: version-1 `mvhd`/`tkhd`/`mdhd`/`elst` past `u32`,
  `co64` instead of `stco` past a 4 GiB chunk offset, and an `mdat` largesize.
  Short files keep the maximally-compatible version-0 layout. Every remaining
  32-bit field is range-checked and throws rather than silently masking.
- **A/V sync: each track gets an `edts`/`elst`** carrying its own composition
  start relative to the earliest track, and the demuxer applies the inverse
  (movie timescale from `mvhd`, leading empty edit + first real `media_time`) to
  both PTS and DTS. A negative-PTS decode preroll is trimmed by the edit list
  rather than presented, so a clip cut at a keyframe starts where it was cut.
- `stss` is omitted when the key set is empty or when every sample is a key —
  an empty `stss` had told players nothing was seekable.
- **Streaming file output.** Given a `FileMuxerOutput`, `Mp4Muxer` writes
  `ftyp` + `mdat` samples straight to the path as they arrive and appends
  `moov` at `finish()`; memory is O(sample count), not O(file). Trap: `moov` is
  at the END (non-faststart, as FFmpeg defaults), and `getBytes()`/
  `outputParts` return `null` in this mode — the bytes went to the file.
  `FileMuxerOutput` on a platform with no filesystem is now refused at
  `createMuxer()` instead of buffering a whole recording that can never be
  saved.
- `Mp4Demuxer.open()` is linear in sample count (the `stsc` lookup no longer
  rescans the table per chunk) — minutes-long interleaved recordings opened in
  seconds.
- AAC `esds`: sample rates >= 65536 write 0 in the 16.16 field (recovered from
  the AudioSpecificConfig on read), 8 channels map to `channelConfiguration` 7,
  and an unmappable channel count throws instead of being clamped.

### MP3 demux + MPEG/ADTS sync

- **New: first-party MP3 demuxer** — `Mp3Demuxer`, wired into
  `ContainerFramingBackend` as `Container.mp3` (demux only; nothing here writes
  mp3). Pure Dart with no `dart:io`/`dart:ffi`, so it runs on web as well as
  native: natively it pairs with the dr_mp3 decoder, and on web it feeds the
  WebCodecs `'mp3'` decoder, which previously had no way to frame an `.mp3` file
  at all (there is no FFmpeg on web).
- Skips ID3v2 (syncsafe size, footer flag, repeated and appended tags) and the
  Xing/Info/VBRI metadata frame; indexes every frame at open; resyncs past
  mid-stream garbage instead of truncating (`resyncCount` reports it). Duration
  is COUNTED from that index rather than estimated from a bitrate, so VBR files
  are exact, and `seek()` is a binary search over it. MPEG-1/2/2.5 Layer III;
  Layer I/II and free-format bitrates are refused at open with a named reason,
  as is a stream that indexes to zero frames. Trap: packets are WHOLE frames
  including the 4-byte header — dr_mp3 and WebCodecs both re-read that header,
  so a stripped payload decodes to nothing.
- **ADTS sync now also requires layer bits `00`** (`isAdtsSync`). The layer
  field was unchecked, so bare mp3 frames (`FF FB`/`FA`/`F3`/`F2`, layer `01`)
  opened as an AAC track, read a "frame length" out of mp3 audio data and hit
  EOF after a packet or two. The sniffer uses the same helpers
  (`isAdtsSync`/`isMp3Sync`, mutually exclusive by construction) and steps over
  an ID3v2 tag before applying them — an `ID3` prefix is legal in front of ADTS
  too, so it is not by itself an mp3 answer.

## 0.6.8

- **ODD frame dimensions no longer break the D3D11 texture path.** NV12
  subsamples chroma 2x2, so a DXGI NV12 surface must have EVEN width and height;
  `CreateTexture2D` returns E_INVALIDARG otherwise. The staging ring was
  allocated at the exact frame size, so a capture like 2576x1119 (odd height --
  window sizes are arbitrary) failed to allocate, `mfenc_ensure_vp` bailed, and
  every texture frame was refused before the import was even attempted. The
  staging surface is now padded up to even; the blt writes only the real region
  via the stream rects and the MFT takes its frame size from the media type, so
  the spare row is never read. Covered by an odd-dimension test that reproduces
  the exact field signature when reverted.
- `MfVideoEncoder` accepts an `existingD3d11Device`, and `MfEncodeBackend`
  passes `BackendContext.d3d11DeviceHandle` into it. Encoding on the device the
  frames already live on removes the per-frame shared-handle import entirely --
  previously the encoder always built its own device via
  `D3D11CreateDevice(NULL, ...)`, i.e. on the DEFAULT adapter, so every GPU
  frame had to be exported and re-opened even in the common case.
- **New: `MfVideoEncoder.lastImportError`** — which step of the D3D11 texture
  import failed, and its HRESULT, now included in the thrown message. "could not
  import" covers a QueryInterface miss, a refused `CreateSharedHandle`, a
  cross-adapter `OpenSharedResource` and a rejected
  `CreateVideoProcessorInputView`; those have nothing in common except the
  symptom, and guessing between them from outside produced several confident
  wrong fixes in a row.
- The zero-copy test now covers both sharing modes (legacy / NT handle) AND both
  pixel formats (BGRA / RGBA, the latter being what the recorder's GPU processor
  actually produces). Each was a case where the test had been agreeing with the
  encoder rather than with real producers.

## 0.6.7

- **New: `MfVideoEncoder.repeatLastFrame(ptsUs)`** — re-encodes the surface most
  recently handed to the MFT under a new timestamp, without importing anything.
  This is what a duplicate/CFR-fill frame actually is, and expressing it by
  re-importing the producer's texture made it depend on a lifetime the producer
  owns: the idle timer fires exactly when that surface is most likely to have
  been recycled, and it fails outright in configurations where nothing is
  writing that texture at all. Returns null when there is nothing to repeat
  (nothing submitted yet, or the last frame was CPU-side), so the caller can
  simply skip the slot.

## 0.6.6

- **Fixes the D3D11 texture import against real GPU producers.** The importer
  only tried `IDXGIResource::GetSharedHandle`, the legacy sharing mode. A
  D3D12/Dawn-backed producer -- minigpu's shared output texture among them --
  publishes an NT handle from `IDXGIResource1::CreateSharedHandle`, for which
  the legacy call simply fails. Every frame was refused, and because the encoder
  skips a refused texture frame the result was a recording with NO VIDEO TRACK
  and no error anywhere. The import now resolves in three steps: same-device
  (no import at all), NT handle via `OpenSharedResource1`, then legacy.
- Sustained failure is no longer silent: 60 consecutive texture-import misses
  now throw, naming adapter mismatch as the likely cause. A single miss is still
  skipped, because the idle-frame duplicator legitimately re-submits a recycled
  texture -- but a run of them is a different fault and must not be quiet.
- TRAP for whoever touches this next: the zero-copy test built its source with
  legacy `MISC_SHARED`, so it agreed with the importer rather than with real
  producers and passed throughout. It now runs both sharing modes, and the
  NT-handle case was verified to FAIL when the new path is ablated.

## 0.6.5

- **MP4 assembly no longer multiplies memory.** The writer buffers every packet
  until `finish()` -- inherent to a whole-file builder -- but it was then
  copying that media three more times: once per payload into a sample list,
  again to concatenate `mdat`, and again to concatenate the final file. Peak was
  4.85x the media at 300 MB of payload; it is now 1.86x, which is the packets
  themselves plus VM overhead, with the muxer adding ~4 MB over simply holding
  them. Payloads needing no rewrite are referenced rather than copied, `mdat`
  offsets are summed instead of concatenated, and the container is emitted as
  ordered pieces via `Mp4Muxer.outputParts` so a file sink streams them.
  `getBytes()` is unchanged for callers that want one buffer -- it just costs
  the concatenation it always did. Measured by
  `benchmark/mp4_muxer_memory.dart`.
- This is a bound, not a licence: a whole-file builder still holds the whole
  file. It suits clips (bounded by the buffer window) and not open-ended
  recording, which streams through FFmpeg.

## 0.6.4

- **`FileMuxerOutput` now actually writes a file.** Every first-party muxer
  (WAV, Ogg, ADTS, MP4/M4A) is a whole-file builder that exposes its result
  through `getBytes()`, and all four ignored the output path completely --
  `writeHeader`/`writePacket`/`finish`/`close` each returned normally and
  nothing reached disk. A caller had no way to detect it and would report
  "saved" to the user. `ContainerFramingBackend.createMuxer` now wraps them so
  the bytes are written on `finish()`; web builds, which have no filesystem,
  raise instead of silently doing nothing. Covered by
  `test/muxer_file_output_test.dart`, which asserts against the filesystem
  rather than against return values.

## 0.6.3

- **Internal pins are now caret ranges, not exact versions.** Exact pins made
  every patch cascade: publishing `miniav_tools_platform_interface` 0.5.3 made
  the already-published `miniav_tools` 0.5.3 and `miniav_tools_ffmpeg` 0.5.3
  unsatisfiable next to it, because they pinned 0.5.2 exactly and nothing in the
  set could move independently. `dart pub publish` warns about this. `release.py
  sync` now normalises to caret so it cannot recur.

## 0.6.2

- **Fixes a broken 0.6.1.** The four native-assets build-hook dependencies
  (`code_assets`, `hooks`, `logging`, `native_toolchain_cmake`) were declared in
  `dev_dependencies`. Consumers do not receive a package's dev_dependencies, so
  `hook/build.dart` could not resolve its own imports and the native asset never
  built downstream — in-repo everything worked, because the dev deps are present
  there. `dart pub publish` reports this as an error; 0.6.1 shipped past it.
  0.6.1 is unusable as a dependency and should be skipped.

## 0.6.1

- **New: `registerFirstPartyBackends()`** — registers every backend in this
  package in one idempotent call. `miniav_recorder` calls it before negotiating
  an encoder, so recording apps now get the FFmpeg-free path (Media Foundation
  hardware H.264/HEVC, OS AAC, first-party MP4 framing) with no per-app setup.
  Registering does not force the outcome: capability is reported honestly and
  FFmpeg still wins where it is the better path. Pin or exclude explicitly with
  `BackendPreference.pinned` / `.excluded`.
- The README previously said this package "self-registers on import". It never
  did, and neither did any other: a top-level `final x = register();` in Dart is
  LAZY, so it runs on first read and nothing reads it. `registerMinigpuBackend`
  had been a no-op for every consumer that did not call it by hand. Covered by
  `test/auto_register_test.dart`, which asserts against the registry rather than
  against the declaration.

- **`Mp4Muxer` now accepts Annex-B H.264/HEVC.** Encoders emit Annex-B
  (start-code framed, parameter sets repeated in-band); MP4 needs an
  `avcC`/`hvcC` configuration record plus length-prefixed NAL samples. The muxer
  decides the framing once from the track's `extraData` — `0x01` means it is
  already a configuration record and is passed through untouched, so remuxing a
  demuxed file does not double-convert. Parameter-set NALs are stripped from the
  samples, which `hvc1` requires.
- New (exported): `isAnnexB`, `splitAnnexB`, `buildAvcC`, `buildHvcC`,
  `annexBToLengthPrefixed` in `src/framing/annexb.dart`. `buildHvcC` parses the
  HEVC SPS (profile_tier_level → chroma_format_idc → bit depths) after removing
  emulation-prevention bytes.
- **D3D11 zero-copy input works for both shapes.** `mfencSendD3d11Texture`
  takes a foreign-device RGBA/BGRA texture (the recorder's GPU processor
  output), imports it via `GetSharedHandle` + `OpenSharedResource`, and converts
  it to NV12 with a D3D11 VideoProcessor — entirely in VRAM. Together with the
  existing shared-NT-handle path this removes the readback from the recorder's
  scale/effects and direct-passthrough paths; `MfVideoEncoder` reports both
  `supportsD3d11TextureInput` and `supportsD3d11SharedHandleInput`.
  Verified by a DIFFERENTIAL test (`test/mf_texture_zero_copy_test.dart`):
  a gradient and a flat-grey source must encode to different sizes. An earlier
  revision produced byte-identical output for both — blank video, while
  reporting success at every step — so "it produced packets" is not a usable
  check here.
- **Fixed a tearing hazard in the D3D11 texture path.** The VideoProcessor
  converted into a single NV12 staging texture, but `ProcessInput` hands the MFT
  a sample that only *references* that surface, so the next frame's conversion
  could overwrite a picture the encoder was still reading. It is now a ring, and
  a slot is only reused once the MFT has released it (detected from the
  reference `MFCreateDXGISurfaceBuffer` holds, calibrated at construction rather
  than assumed). When every slot is in flight the encoder reports the same
  "drain and retry" it uses for `MF_E_NOTACCEPTING`, which is self-clearing.
- The texture path allocates nothing per frame: the imported source, its input
  view, the output views, the rects and the blt fence are all built once.
  `IDXGIKeyedMutex::AcquireSync` no longer waits `INFINITE` — a producer that
  never released would have hung the recording rather than dropped a frame.
  Measured cost of the whole path at 2560x1440 fed at 60 fps is 0.60 ms/frame
  mean, 0.91 ms p99 (`benchmark/mf_texture_bench.dart`); the caching itself is
  not where that comes from — ablating it moves nothing, so it is kept for the
  allocation churn rather than for the clock.
- `MfVideoEncoder.supportsD3d11Input` and `.isHardware` are cached. Both are
  fixed at session creation, and every native call is marshalled to the MTA
  worker thread, so re-answering them per frame spent a cross-thread round-trip
  on a constant.
- **MF encode now works on an STA thread — i.e. inside Flutter at all.** MF
  requires MTA; `CoInitializeEx(COINIT_MULTITHREADED)` fails with
  `RPC_E_CHANGED_MODE` on a thread already initialised STA, which Flutter's UI
  thread is. Every entry point therefore reported "no MFT" in any Flutter app
  (measured: `has_mft`=0, `list_hw`=-1) and the encoder silently lost every
  negotiation. `mf_encoder.c` now owns a dedicated MTA worker thread and
  marshals every public call onto it — chosen over an isolate host because
  D3D11 shared handles are process-wide and cross a thread hop for free, so
  zero-copy survives. Jobs run one at a time; concurrent *sessions* serialise.
  Pinned by `test/mf_sta_thread_test.dart`.
- **`MfEncodeBackend` is now the primary Windows H.264/HEVC encoder**: priority
  45 → 55, and it reports a *hardware* capability. It previously answered
  `false` to `supportsEncode(codec, hwAccel: true)`, so despite running on the
  OS hardware MFT it never advertised a hardware path — and `isHardware` outranks
  priority in the negotiator, so no priority bump alone could have promoted it.
  The hardware claim is gated on the OS actually listing a hardware MFT, so a
  software-only machine still ranks below a real hardware FFmpeg path.
- `MfVideoEncoder` accepts every frame source the backend advertises: CPU NV12
  and I420, `FrameSource.yuv420p`, and per-plane `miniavBufferCpu` (honouring
  each plane's stride). Previously anything but a packed `CpuFrameSource` NV12
  threw — including the D3D11 zero-copy branch's own fallback, which would have
  killed a recording rather than degrading to a readback.
- `MfEncodeBackend.hasHardwareMft` no longer caches a *failure to enumerate*.
  The hardware-MFT answer is per **apartment**, not per machine: MF needs MTA,
  and on an STA thread (Flutter's UI thread) `mfencListHw` returns -1. Caching
  that as "no hardware" poisoned the static cache for every later caller,
  including an MTA isolate where the same machine answers yes. Only a
  definitive result is cached now.
- `MfVideoEncoder` reports `supportsD3d11SharedHandleInput` (true whenever the
  D3D11 device manager bound) and `supportsD3d11TextureInput` = false: it opens
  a capture's shared NT handle on its own device, but cannot take the GPU
  processor's foreign-device RGBA texture. The recorder uses these to pick its
  screen zero-copy path. When the handle cannot be opened the encoder now throws
  a `CodecRuntimeException` naming the likely adapter mismatch — a GPU-resident
  buffer has no CPU pixels to fall back to, so the old path reported "needs CPU
  NV12", which named the symptom and hid the cause.
- `MfVideoEncoder.extraData` falls back to harvesting the parameter sets from
  the first keyframe when the MFT publishes no `MF_MT_MPEG_SEQUENCE_HEADER`
  (NVIDIA's do; this covers the vendors that don't). A null there would fail the
  track at mux time.

## 0.5.2

## 0.5.1

## 0.5.0

- Version bump to keep the miniav_tools family in lockstep; no changes in this package.

## 0.4.10

## 0.4.9

- Increment to keep in step with others.

## 0.4.8

- Increment to keep in step with others.

## 0.4.7

- Increment to keep in step with others.

## 0.4.6

- Increment to keep in step with others.

## 0.4.5

- Version bump for coordinated release with `miniav_recorder` 0.4.5
  (`Recorder.sharedGpu` getter, `GpuScreenProcessor` public export).

## 0.4.4

- fixing recorder loopback drift

## 0.4.3

- audio data issue, increment miniav

## 0.4.2

- fix timing issue

## 0.4.1

- fix audio timing, add frame duplication

## 0.4.0

- fix frame rate scheduling

## 0.3.12

- fused shader cache fix

## 0.3.11

- Use GPU until we cant.

## 0.3.9

- AMF Fix, fix unknown audio error

## 0.3.8

- Fix vendor Order

## 0.3.7

- fix NV12 path

## 0.3.6

- fix cpu path

## 0.3.5

- fix recorder sync drift

## 0.3.4

- attempt fix resolution issue

## 0.3.3

- fix precheck

## 0.3.2

- fix property

## 0.3.1

- fix scaling crazy, attempt fix other HW encoders

## 0.3.0

- fix recorder logging, Tier A path, deps to 1.5.0

## 0.2.21

- increments minigpu to 1.4.15

## 0.2.20

- increments minigpu to 1.4.14

## 0.2.19

- increments minigpu to 1.4.12

## 0.2.18

- increments minigpu to 1.4.11

## 0.2.17

- increments minigpu to 1.4.9

## 0.2.16

- increments minigpu to 1.4.8, hopefully fix cpu fallback

## 0.2.15

- increments minigpu to 1.4.7

## 0.2.14

- fixes unicode, increments minigpu to 1.4.7

## 0.2.12

- Increment minigpu to 1.4.6

## 0.2.11

## 0.2.9

## 0.2.8

- add RecorderLogSource.minigpu: routes native minigpu/Dawn log lines through the unified Recorder log callback; Recorder.minigpuLevelFor public helper for tests; 12 new tests in log_level_test.dart

## 0.2.7

- fix FormatException on non-UTF-8 bytes in MiniAV log callback: use Utf8Decoder(allowMalformed: true) instead of toDartString()
- Increment minigpu to 1.4.4

## 0.2.5

## 0.2.4

## 0.2.3

## 0.2.2-WIP

- add unified Recorder.setLogLevel and Recorder.setLogCallback routing all native logs (MiniAV + FFmpeg) through a single Dart callback

## 0.2.1

- fixes dawn find issue

## 0.2.0

- add more quality control, fix ffmpeg usage issue

## 0.1.9

- fixes timestamp issues

## 0.1.8

- recorder scaling, warmup feature

## 0.1.7

- adds transform effects

## 0.1.6

- adds clip buffer

## 0.1.5

- fix loopback issue

## 0.1.4

- fix loopback issue, add tests

## 0.1.3

- update with fixes

## 0.1.2

- recorder sync and multi files

## 0.1.1

- updated to latest miniav/minigpu deps

## 0.1.0

- Initial release. Pure-WGSL codec backend for `miniav_tools` running entirely
  on minigpu's WebGPU compute pipeline.
- MJPEG encoder: RGBA → YCbCr → DCT → quantize → Huffman → JFIF emitted as a
  self-contained `.jpg` byte stream (plays in browsers, VLC, QuickTime,
  ffmpeg). No native FFmpeg dependency — works anywhere minigpu works,
  including web (WebGPU).
- `crfQuality` 1..31 maps to JPEG quality 90..10 for parity with FFmpeg's
  `-q:v` semantics.
