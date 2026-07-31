/// Media Foundation requires MTA, and Flutter's UI thread is STA — so before
/// `mf_encoder.c` grew its own MTA worker thread, every entry point returned
/// "no MFT" inside any Flutter app and the encoder silently lost every
/// negotiation. Measured then: `mfencHasMft(h264)=0`, `mfencListHw(h264)=-1`.
///
/// This pins the fix. It is the only test that runs MF from a genuinely STA
/// thread, so a regression in the worker (or someone "simplifying" it away)
/// shows up here and nowhere else.
///
/// TRAP: the STA init MUST come first. Any earlier MF call CoInitializes this
/// thread as MTA, after which the STA request returns RPC_E_CHANGED_MODE, the
/// thread stays MTA, and the test passes while proving nothing. That exact
/// mistake was made once while diagnosing this.
@TestOn('vm')
library;
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:miniav_tools_codecs/miniav_tools_codecs.dart';
import 'package:miniav_tools_codecs/src/codecs_native.dart';
import 'package:test/test.dart';

typedef _CoInitNative = Int32 Function(Pointer<Void>, Int32);
typedef _CoInit = int Function(Pointer<Void>, int);
const _sta = 0x2;

void main() {
  test('MF works from an STA thread (Flutter UI thread situation)', () async {
    // STA FIRST — any earlier MF call would put this thread in MTA and
    // invalidate the whole test (that mistake already happened once).
    final ole32 = DynamicLibrary.open('ole32.dll');
    final coInit = ole32.lookupFunction<_CoInitNative, _CoInit>('CoInitializeEx');
    final hr = coInit(nullptr, _sta);
    print('CoInitializeEx(STA) hr=0x${(hr & 0xFFFFFFFF).toRadixString(16)}');
    expect(hr, 0, reason: 'thread must be genuinely STA for this to mean anything');

    print('STA: mfencHasMft(h264)=${mfencHasMft(0)}');
    final buf = calloc<Uint8>(1024);
    print('STA: mfencListHw(h264)=${mfencListHw(0, buf, 1024)}');
    calloc.free(buf);

    final enc = await MfVideoEncoder.open(const EncoderConfig(
      codec: VideoCodec.h264, width: 320, height: 240, bitrateBps: 2000000,
      frameRateNumerator: 30, frameRateDenominator: 1, gopLength: 30));
    print('STA: open -> ${enc == null ? "NULL" : "ok"}');
    expect(enc, isNotNull, reason: 'MF must open on an STA thread now');
    print('STA: isHardware=${enc!.isHardware} mft="${enc.mftName}"');
    expect(enc.isHardware, isTrue);

    var n = 0;
    for (var i = 0; i < 10; i++) {
      final y = Uint8List(320 * 240 + 320 * 120);
      for (var k = 0; k < 320 * 240; k++) { y[k] = ((k ~/ 320) + i * 7) & 0xFF; }
      y.fillRange(320 * 240, y.length, 128);
      final p = await enc.encode(FrameSource.cpu(bytes: y,
        pixelFormat: MiniAVPixelFormat.nv12, width: 320, height: 240,
        timestampUs: i * 33333));
      if (p != null) n++;
    }
    n += (await enc.flush()).length;
    print('STA: encoded $n packets');
    expect(n, greaterThan(0));
    await enc.close();
  });
}
