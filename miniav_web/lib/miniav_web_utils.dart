part of './miniav_web.dart';

/// Internal utilities for web implementation
class _WebUtils {
  static Uint8List _imageDataToUint8List(web.ImageData imageData) {
    return Uint8List.fromList(imageData.data.toDart);
  }

  static MiniAVVideoBuffer _createVideoBufferFromImageData(
    web.ImageData imageData,
  ) {
    final data = _imageDataToUint8List(imageData);
    return MiniAVVideoBuffer(
      width: imageData.width,
      height: imageData.height,
      pixelFormat: MiniAVPixelFormat.rgba32,
      strideBytes: [imageData.width * 4], // RGBA = 4 bytes per pixel
      planes: [data],
    );
  }

  static int _getCurrentTimestampUs() {
    return DateTime.now().microsecondsSinceEpoch;
  }
}
