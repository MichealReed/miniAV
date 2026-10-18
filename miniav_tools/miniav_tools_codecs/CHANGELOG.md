# Changelog

## 0.8.1

- The bundled web worker payloads (codec, demux and audio playback) are
  rebuilt with spawn 0.1.2 and this release's sources; they had not been
  rebuilt since August. Each is about 32 kB larger.
- Requires spawn ^0.1.2.

## 0.8.0

- Opening the web audio sink can be cancelled while its worklet module loads,
  and a cancelled opening closes its `AudioContext` even if loading stalls. A
  declared channel fallback is chosen before any asynchronous step, so it uses
  the `AudioContext` the user gesture activated.
- Media Foundation encoder: a texture frame is no longer encoded while its
  producer may still be drawing it. A frame whose keyed mutex is not acquired
  within 8 ms, or whose conversion has not finished within 100 ms, is dropped
  instead of being read unlocked or encoded early; 60 failures in a row still
  end the session.
- **Behaviour change:** a producer that releases its texture under a keyed-mutex
  key other than 0 has its frames dropped (they used to be read unlocked), and
  the reported reason says so.
- Media Foundation encoder: a frame passed as a capture's shared handle is
  copied (or converted, unless it is NV12 at the encoder's size) into the
  encoder's own surface before `encode` returns, so the capture can reuse its
  texture once the frame is released. The hardware encoder used to read the
  capture's texture later; with an NVIDIA encoder, a camera frame faulted the
  GPU and nothing more was encoded.
- A removed encoder device is reported as such instead of being blamed on the
  capture.
- The build hook registers the native C sources, so editing them rebuilds the
  library here and in dependent packages.
- `MfVideoEncoder` implements `FrameRepeatingEncoder`, so a pacer can re-send
  the last frame through the shared interface.
- New `mfencCreateGpuOnDevice` (native address
  `mfencGpuOnDeviceCreateFunction`): a hardware Media Foundation encoder on the
  caller's own D3D11 device. It never creates its own device or falls back to
  software, accepts only textures on that device, and reports back-pressure
  until the encoder has released its samples.
- Web capability detection no longer throws when compiled with dart2wasm.
- Requires miniav_platform_interface 0.8.0 and
  miniav_tools_platform_interface 0.6.0.

## 0.7.7

- Requires spawn ^0.1.1: native transfers actually transfer, and a web message
  the worker cannot deserialize is reported instead of vanishing.

## 0.7.6

- The MP4 writer accepts a video track before its encoder has published its
  configuration record; supply the record later with `setTrackConfig`. Some
  hardware H.264 encoders (Intel Quick Sync) withhold it until their first
  output, and on those machines recordings fell back to FFmpeg. Output is
  identical to supplying the record at open.
- New `Mp4Muxer.tracksMissingConfig` reports a track whose record never arrived
  instead of throwing: its samples are written but it will not decode, and the
  other tracks are unaffected.

## 0.7.5

- Increment downstream deps

## 0.7.4

- MP4: a decode timestamp that steps backwards is repaired instead of refused.
  `finish()` used to throw and leave a file with no `moov` that no player opens,
  so one reordered packet lost the whole recording. Reordered packets are
  counted as they arrive and clamped forward when the index is built, both
  reported by `Mp4Muxer.timingReports`; recordings without reordering are
  unchanged. `finish()` no longer leaks the file handle when the index cannot be
  built.
- MP4: a track's codec configuration record can change mid-recording through
  `Mp4Muxer.setTrackConfig`, for an encoder reopened after a graphics device
  reset. A different record gets its own sample entry; an identical one is
  ignored.
- Media Foundation: a shared-handle import failure tells an encoder on a
  different adapter apart from a capture that stopped, instead of always blaming
  the adapter.
- `AudioRingSink.open` declines a channel count the destination cannot carry
  (`destination.maxChannelCount`), so a surround request on stereo hardware
  falls back cleanly instead of being silently down-mixed. Above two channels
  the sink maps channels discretely, so a finished multichannel speaker feed is
  not remixed by Web Audio.

## 0.7.3

- Wasm codecs load inside Web Workers; they used to fall back silently to
  WebCodecs there.

## 0.7.2

- Web audio can play entirely off the main thread: an AudioWorklet reads decoded
  PCM from shared memory that a worker fills, so a busy main thread no longer
  starves playback.
- WebCodecs decoders: a packet passed to `decode()` while a frame was buffered
  was dropped, breaking every later frame, and both decoders passed the whole
  backing buffer instead of the packet's bytes.
- Decoders wait on the output callback instead of polling a timer the browser
  clamps to 4 ms, taking audio decode from 5.0 ms to 0.1 ms per packet.
- Worker-hosted demux and decode are available with `backendOptions['worker'] =
  'true'`.
- Exposes the Media Foundation encoder's bound D3D11 device.
- The `decodeAudioData` fallback decodes AAC, so browsers without WebCodecs
  audio can play it.

## 0.7.1

- released 08/13/26 - MR

## 0.7.0

- **Behaviour change:** `MfVideoEncoder.flush()` throws a
  `CodecRuntimeException` instead of returning an empty list when the drain does
  not finish, or when the session accepted frames but never produced a packet.
  The flush deadline is 2 s without output, so concurrent sessions no longer cut
  a healthy drain short. Packets can come back from either `encode()` or
  `flush()`; count both.
- New, test-only `mfencSetFault(handle, mode)` makes one encoder session
  simulate a drain that never completes (mode 1) or a session that produces no
  packets (mode 2).
- libopus is built thread-safe on Windows. Its previous build mode shared one
  scratch buffer across the process, so two threads using Opus at once corrupted
  the heap and crashed later in unrelated code. New `opusScratchMode()` (native
  `miniav_opus_scratch_mode()`) reports the compiled mode.
- The Opus encoder writes libopus's real lookahead as the OpusHead pre-skip (new
  native export `miniav_opus_enc_lookahead`). It wrote 0, so every file began
  with the encoder's priming as audible audio and ran ~6.5 ms ahead of video.
- WAV demux reads `WAVE_FORMAT_EXTENSIBLE`, 24-bit and 8-bit PCM, so most
  multichannel and 24-bit files open. 8-bit converts to `pcmS16le` and 24-bit to
  `pcmF32le`, both exactly; 32-bit integer and 64-bit float still go to FFmpeg.
- The container sniffer requires a RIFF file's form type to be `WAVE`; `.avi`,
  WebP and other RIFF files went to the WAV parser, which on the web, with no
  fallback, was fatal. `ContainerFramingBackend.sniff` is public.
- Ogg/Opus duration, packet timestamps and seeking come from the duration each
  packet declares and the page granule positions, instead of assuming 20 ms
  packets, which were off by up to 3x for 10/40/60 ms packets. `OggMuxer` writes
  granule positions the same way.
- `Mp4Demuxer.durationUs` includes the last sample's duration; files read back
  one sample short.
- `AdtsDemuxer.durationUs` is no longer null: it is computed on first read and
  cached, so a plain `.aac` file gets a seek bar.
- `WavMuxer` and `AdtsMuxer` stream to a `FileMuxerOutput` instead of holding
  the whole recording in memory (both report `ownsFileOutput`; `getBytes()`
  returns null in that mode; new `MuxerFileSink.patchU32Le`). `WavDemuxer` reads
  an interrupted recording's unfinished `data` chunk to the end of the file.
  `OggMuxer` still buffers.
- The Media Foundation video decoder crops to the display aperture: frames
  reported the padded coded size (1080 as 1088) with padding rows as picture.
  `readBytes()` now returns exactly `width * height * 3 / 2`. The D3D11 texture
  stays at the coded size with the picture top-left, so import it with the
  frame's `width`/`height`.
- `SwAudioDecoder` emits MP3 audio as it decodes (in ~16 KiB batches) instead of
  withholding everything until `flush()`, which left a streaming player silent
  until the end of the file. Output is sample-identical to a whole-file decode.
- `SwAudioBackend` no longer claims FLAC or Vorbis decode, which route to
  FFmpeg: streamed FLAC/Vorbis through it never worked, and it outranked FFmpeg,
  so nothing took over. `SwAudioDecoder` still decodes whole-file feeds of all
  three codecs.
- `Mp4Demuxer.seek` lands on a video keyframe at or before the target; in an
  interleaved file it used to land in the middle of a video GOP. Audio-only
  files are unchanged.
- ADTS demux skips leading and trailing ID3 tags and resyncs past corrupt
  frames, where one bad frame used to silently truncate the rest of the file;
  timestamps account for the skipped span. `channel_configuration` 7 maps to 8
  channels.
- The Media Foundation HEVC decoder reads the frame size from the SPS in
  `extraData` when `DecoderConfig.width`/`height` are unset, and declines
  (falling back to software) when there is none. It used to accept packets and
  produce nothing: a black screen with no error. H.264 is unaffected.
- `Mp4Muxer` writes the display matrix for `VideoTrackInfo.rotationDegrees`
  (0/90/180/270 clockwise, as ffmpeg writes it), so portrait recordings no
  longer play sideways.

## 0.6.9

### Media Foundation video encoder

- `flush()` no longer wedges the session or drops the tail, and `encode()` after
  `flush()` keeps encoding. New `mfencDrainState` lets `flush()` wait until the
  drain completes.
- New `MfVideoEncoder.invalidateImports()`. The D3D11 import cache holds a
  reference to each producer texture, so a recycled texture address no longer
  encodes the previous picture (a frozen frame). Call it on a resolution change
  or a rebuilt texture ring to release those textures.
- CPU NV12/I420 input accepts odd dimensions.
- Texture import failures and back-pressure are reported separately, each
  failure with its cause.
- `MfVideoEncoder` is `Finalizable`, and its native reads throw `StateError`
  after `close()` instead of using a freed handle.

### ISO-BMFF muxer / demuxer

- B-frame timestamps are correct: `stts` is derived from DTS, and a `ctts` box
  is written when any packet has `ptsUs != dtsUs`. Strictly decreasing DTS
  throws instead of producing a broken file.
- Large files use 64-bit fields (durations, chunk offsets past 4 GiB, `mdat`
  size); short files keep the most compatible layout. Every remaining 32-bit
  field is range-checked.
- A/V sync: each track gets an edit list placing its start relative to the
  earliest track, and the demuxer applies it. A negative-PTS preroll is trimmed,
  so a clip cut at a keyframe starts where it was cut.
- `stss` is omitted when no sample, or every sample, is a keyframe; an empty
  `stss` told players nothing was seekable.
- Streaming file output: given a `FileMuxerOutput`, `Mp4Muxer` writes samples to
  the file as they arrive and appends `moov` at `finish()`, so memory grows with
  the sample count, not the file. `moov` is at the end (not faststart), and
  `getBytes()`/`outputParts` return `null` in this mode. `FileMuxerOutput` on a
  platform without a filesystem is refused at `createMuxer()`.
- `Mp4Demuxer.open()` is linear in the sample count; long interleaved recordings
  took seconds to open.
- AAC `esds`: sample rates of 65536 and above and 8 channels are written
  correctly, and an unmappable channel count throws instead of being clamped.

### MP3 demux + MPEG/ADTS sync

- New first-party MP3 demuxer, `Mp3Demuxer` (`Container.mp3`, demux only). It is
  pure Dart, so it also runs on web, where it feeds the WebCodecs `'mp3'`
  decoder; the web could not play an `.mp3` file before.
- It skips ID3v2 tags and the Xing/Info/VBRI frame, resyncs past garbage
  (`resyncCount`), and counts duration from a frame index, so VBR files are
  exact and `seek()` is precise. MPEG-1/2/2.5 Layer III only; other streams are
  refused at open with a reason.
- ADTS sync also requires layer bits `00` (`isAdtsSync`), so a bare MP3 file is
  no longer opened as AAC. The sniffer uses `isAdtsSync`/`isMp3Sync` and looks
  past an ID3v2 tag before deciding.

## 0.6.8

- Odd frame dimensions no longer break the D3D11 texture path: a capture with an
  odd width or height had every texture frame refused. The NV12 staging surface
  is padded to even sizes.
- `MfVideoEncoder` accepts an `existingD3d11Device`, and `MfEncodeBackend`
  passes it `BackendContext.d3d11DeviceHandle`, so frames already on that device
  are encoded without a per-frame shared-handle import.
- New `MfVideoEncoder.lastImportError`: which step of the D3D11 texture import
  failed and its HRESULT, also included in the thrown message.

## 0.6.7

- New `MfVideoEncoder.repeatLastFrame(ptsUs)` re-encodes the last submitted
  surface under a new timestamp without importing anything, for duplicate and
  constant-frame-rate fill frames. Re-importing depended on a producer texture
  that may already have been recycled. Returns null when there is nothing to
  repeat.

## 0.6.6

- The D3D11 texture import works with real GPU producers. D3D12/Dawn producers
  (minigpu's shared output texture among them) publish NT handles, which the
  importer did not try, so every frame was refused and the recording had no
  video track and no error. The import now tries the same device, then the NT
  handle, then the legacy handle.
- 60 consecutive texture-import failures throw, naming an adapter mismatch as
  the likely cause; a single miss is still skipped.

## 0.6.5

- MP4 assembly no longer copies the media several times: peak memory was 4.85x
  the media at 300 MB of payload and is now 1.86x. The file is emitted in pieces
  through `Mp4Muxer.outputParts`; `getBytes()` is unchanged. The muxer still
  holds the whole file, so it suits clips; open-ended recording streams through
  FFmpeg.

## 0.6.4

- `FileMuxerOutput` writes a file. Every first-party muxer (WAV, Ogg, ADTS,
  MP4/M4A) ignored the output path, so nothing reached disk and nothing reported
  it. `ContainerFramingBackend.createMuxer` now writes the bytes on `finish()`;
  web builds, which have no filesystem, throw instead.

## 0.6.3

- Internal dependencies are caret ranges instead of exact pins, which made each
  patch release unsatisfiable next to already-published packages.

## 0.6.2

- Fixes a broken 0.6.1, whose build-hook dependencies (`code_assets`, `hooks`,
  `logging`, `native_toolchain_cmake`) were dev dependencies, so the native
  asset never built downstream. Skip 0.6.1.

## 0.6.1

- New `registerFirstPartyBackends()` registers every backend in this package in
  one idempotent call. `miniav_recorder` calls it before choosing an encoder, so
  recording apps get the FFmpeg-free path (Media Foundation hardware H.264/HEVC,
  OS AAC, first-party MP4) without setup. FFmpeg still wins where it is better;
  `BackendPreference.pinned` / `.excluded` override the choice.
- The README no longer claims this package registers itself on import. It never
  did, and `registerMinigpuBackend` must also be called explicitly.
- `Mp4Muxer` accepts Annex-B H.264/HEVC: it builds the `avcC`/`hvcC` record,
  length-prefixes the samples and strips parameter sets. A configuration record
  in `extraData` is passed through, so remuxing does not convert twice.
- New exports `isAnnexB`, `splitAnnexB`, `buildAvcC`, `buildHvcC` and
  `annexBToLengthPrefixed`.
- D3D11 zero-copy input: `mfencSendD3d11Texture` takes a texture from another
  device (RGBA/BGRA), imports it and converts it to NV12 on the GPU. With the
  shared NT handle path, this removes the readback from the recorder's GPU
  paths. `MfVideoEncoder` reports `supportsD3d11TextureInput` and
  `supportsD3d11SharedHandleInput`, and a handle that cannot be opened throws a
  `CodecRuntimeException` naming the likely adapter mismatch.
- Fixed tearing in the D3D11 texture path: the next frame's conversion could
  overwrite a picture the encoder was still reading. Conversions use a ring of
  surfaces, each reused only once the encoder has released it; when all are in
  flight the encoder reports back-pressure.
- The texture path allocates nothing per frame (about 0.6 ms per frame at
  2560x1440, 60 fps), and the keyed-mutex wait is bounded, so a producer that
  never releases costs a frame instead of hanging the recording.
- `MfVideoEncoder.supportsD3d11Input` and `isHardware` are cached.
- Media Foundation encoding works on an STA thread, and so inside Flutter: every
  entry point reported no encoder in a Flutter app, so it silently lost every
  negotiation. All calls run on a dedicated MTA worker thread; concurrent
  sessions take turns.
- `MfEncodeBackend` is the primary Windows H.264/HEVC encoder: priority 45 → 55,
  and it reports hardware capability when the OS lists a hardware encoder, so a
  software-only machine still ranks below hardware FFmpeg.
- `MfEncodeBackend.hasHardwareMft` no longer caches a failure to enumerate: a
  caller on Flutter's UI thread poisoned the answer for everyone.
- `MfVideoEncoder` accepts every frame source the backend advertises: CPU NV12
  and I420, `FrameSource.yuv420p` and per-plane `miniavBufferCpu` with strides.
  Anything else used to throw, including the zero-copy path's own fallback.
- `MfVideoEncoder.extraData` falls back to the parameter sets in the first
  keyframe when the encoder publishes no sequence header; a null failed the
  track at mux time.

## 0.5.2

## 0.5.1

## 0.5.0

- Version bump to keep the miniav_tools family in lockstep; no changes in this
  package.

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

- Version bump for the coordinated release with `miniav_recorder` 0.4.5.

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

- Add `RecorderLogSource.minigpu`, routing native minigpu/Dawn log lines through
  the unified `Recorder` log callback, and the public `Recorder.minigpuLevelFor`
  helper.

## 0.2.7

- Fix a FormatException on non-UTF-8 bytes in the MiniAV log callback.
- Increment minigpu to 1.4.4

## 0.2.5

## 0.2.4

## 0.2.3

## 0.2.2-WIP

- add unified Recorder.setLogLevel and Recorder.setLogCallback routing all
  native logs (MiniAV + FFmpeg) through a single Dart callback

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
- MJPEG encoder producing self-contained JPEG frames that browsers, VLC,
  QuickTime and ffmpeg play. No FFmpeg needed, so it works wherever minigpu
  does, including the web.
- `crfQuality` 1..31 maps to JPEG quality 90..10, matching FFmpeg's `-q:v`.
