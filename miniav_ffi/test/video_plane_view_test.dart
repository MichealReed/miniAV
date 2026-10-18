// CPU plane views must cover exactly the bytes a frame has. A view that runs
// past the end of a native frame crashes the reader or hands it unrelated
// memory; the chroma planes of 4:2:0 formats used to get the full frame height
// and MJPEG a view sized like raw pixels.
//
// The buffers below are filled in by hand: no capture device, no native call
// except the damage lookup, which returns nothing for a buffer that no backend
// produced.

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:miniav_ffi/miniav_ffi_bindings.dart' as bindings;
import 'package:miniav_ffi/miniav_ffi_types.dart';
import 'package:miniav_platform_interface/miniav_platform_types.dart';
import 'package:test/test.dart';

typedef _F = bindings.MiniAVPixelFormat;
typedef _C = bindings.MiniAVBufferContentType;

void main() {
  late ffi.Pointer<bindings.MiniAVBuffer> buffer;
  late ffi.Pointer<ffi.Uint8> pixels;

  setUp(() {
    buffer = calloc<bindings.MiniAVBuffer>();
    pixels = calloc<ffi.Uint8>(1 << 16);
  });
  tearDown(() {
    calloc.free(buffer);
    calloc.free(pixels);
  });

  // Byte lengths of the plane views for a 64 x 35 frame whose planes start at
  // the given offsets into `pixels`, with the given strides.
  List<int> viewLengths(
    _F format,
    List<({int offset, int stride})> planes, {
    _C content = _C.MINIAV_BUFFER_CONTENT_TYPE_CPU,
    int dataSizeBytes = 0,
  }) {
    final native = buffer.ref;
    native.typeAsInt = bindings.MiniAVBufferType.MINIAV_BUFFER_TYPE_VIDEO.value;
    native.content_typeAsInt = content.value;
    native.data_size_bytes = dataSizeBytes;
    final video = native.data.video;
    video.info.width = 64;
    video.info.height = 35;
    video.info.pixel_formatAsInt = format.value;
    video.num_planes = planes.length;
    for (var i = 0; i < planes.length; ++i) {
      video.planes[i].data_ptr = (pixels + planes[i].offset).cast();
      video.planes[i].stride_bytes = planes[i].stride;
    }
    final frame = MiniAVBufferFFI.fromPointer(buffer).data as MiniAVVideoBuffer;
    return [
      for (final plane in frame.planes.take(planes.length)) plane!.length,
    ];
  }

  test('4:2:0 chroma planes hold half the rows, rounded up', () {
    const y = 64 * 35;
    for (final format in [
      _F.MINIAV_PIXEL_FORMAT_NV12,
      _F.MINIAV_PIXEL_FORMAT_NV21,
    ]) {
      expect(
        viewLengths(format, [(offset: 0, stride: 64), (offset: y, stride: 64)]),
        [y, 64 * 18],
        reason: format.name,
      );
    }
    for (final format in [
      _F.MINIAV_PIXEL_FORMAT_I420,
      _F.MINIAV_PIXEL_FORMAT_YV12,
    ]) {
      expect(
        viewLengths(format, [
          (offset: 0, stride: 64),
          (offset: y, stride: 32),
          (offset: y + 32 * 18, stride: 32),
        ]),
        [y, 32 * 18, 32 * 18],
        reason: format.name,
      );
    }
    expect(
      viewLengths(_F.MINIAV_PIXEL_FORMAT_YUV420_10BIT, [
        (offset: 0, stride: 128),
        (offset: 128 * 35, stride: 128),
      ]),
      [128 * 35, 128 * 18],
    );
  });

  test('every other plane spans its stride times the frame height', () {
    expect(
      viewLengths(_F.MINIAV_PIXEL_FORMAT_BGRA32, [(offset: 0, stride: 256)]),
      [256 * 35],
    );
    expect(
      viewLengths(_F.MINIAV_PIXEL_FORMAT_YUY2, [(offset: 0, stride: 128)]),
      [128 * 35],
    );
    // 4:2:2 halves the chroma horizontally only.
    expect(
      viewLengths(_F.MINIAV_PIXEL_FORMAT_YUV422_10BIT, [
        (offset: 0, stride: 128),
        (offset: 128 * 35, stride: 64),
        (offset: 192 * 35, stride: 64),
      ]),
      [128 * 35, 64 * 35, 64 * 35],
    );
  });

  test('an MJPEG frame is one plane of dataSizeBytes', () {
    // Windows reports a raw-pixel stride for it, Linux and Android none.
    for (final stride in [64 * 4, 0]) {
      expect(
        viewLengths(_F.MINIAV_PIXEL_FORMAT_MJPEG, [
          (offset: 0, stride: stride),
        ], dataSizeBytes: 1234),
        [1234],
        reason: 'stride $stride',
      );
    }
  });

  test('GPU frames have empty planes whatever their pointers hold', () {
    expect(
      viewLengths(_F.MINIAV_PIXEL_FORMAT_BGRA32, [
        (offset: 0, stride: 0),
      ], content: _C.MINIAV_BUFFER_CONTENT_TYPE_GPU_D3D11_HANDLE),
      [0],
    );
    // A Linux DMA-BUF camera frame puts its file descriptor in the plane
    // pointer and its row pitch in the stride: no CPU view may be built on it.
    expect(
      viewLengths(_F.MINIAV_PIXEL_FORMAT_NV12, [
        (offset: 0, stride: 64),
      ], content: _C.MINIAV_BUFFER_CONTENT_TYPE_GPU_DMABUF_FD),
      [0],
    );
  });
}
