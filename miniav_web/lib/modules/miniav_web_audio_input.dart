part of '../miniav_web.dart';

/// Web implementation of [MiniAudioInputPlatformInterface]
class MiniAVWebAudioInputPlatform implements MiniAudioInputPlatformInterface {
  @override
  Future<List<MiniAVDeviceInfo>> enumerateDevices() async {
    try {
      final devices =
          await web.window.navigator.mediaDevices.enumerateDevices().toDart;
      final audioDevices = <MiniAVDeviceInfo>[];

      for (final device in devices.toDart) {
        if (device.kind == 'audioinput') {
          audioDevices.add(
            MiniAVDeviceInfo(
              deviceId: device.deviceId,
              name:
                  device.label.isNotEmpty
                      ? device.label
                      : 'Microphone ${audioDevices.length + 1}',
              isDefault: audioDevices.isEmpty, // First device as default
            ),
          );
        }
      }

      return audioDevices;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<MiniAVAudioInfo>> getSupportedFormats(String deviceId) async {
    // Web Audio API typically supports these formats
    return [
      MiniAVAudioInfo(
        format: MiniAVAudioFormat.f32,
        sampleRate: 44100,
        channels: 1,
        numFrames: 1024,
      ),
      MiniAVAudioInfo(
        format: MiniAVAudioFormat.f32,
        sampleRate: 44100,
        channels: 2,
        numFrames: 1024,
      ),
      MiniAVAudioInfo(
        format: MiniAVAudioFormat.f32,
        sampleRate: 48000,
        channels: 1,
        numFrames: 1024,
      ),
      MiniAVAudioInfo(
        format: MiniAVAudioFormat.f32,
        sampleRate: 48000,
        channels: 2,
        numFrames: 1024,
      ),
    ];
  }

  @override
  Future<MiniAVAudioInfo> getDefaultFormat(String deviceId) async {
    return MiniAVAudioInfo(
      format: MiniAVAudioFormat.f32,
      sampleRate: 44100,
      channels: 1,
      numFrames: 1024,
    );
  }

  @override
  Future<MiniAudioInputContextPlatformInterface> createContext() async {
    return MiniAVWebAudioInputContext();
  }
}

/// Web implementation of [MiniAudioInputContextPlatformInterface]
class MiniAVWebAudioInputContext implements MiniAudioInputContextPlatformInterface {
  web.MediaStream? _mediaStream;
  web.AudioContext? _audioContext;
  web.MediaStreamAudioSourceNode? _sourceNode;
  web.ScriptProcessorNode? _processorNode;
  StreamController<MiniAVBuffer>? _bufferController;

  MiniAVAudioInfo? _currentFormat;
  void Function(MiniAVBuffer buffer, dynamic userData)? _onData;
  dynamic _userData;

  @override
  Future<void> configure(String deviceId, MiniAVAudioInfo format) async {
    await destroy();

    // Create constraints using the proper web API types
    final constraints = web.MediaStreamConstraints(
      audio: _createAudioConstraints(deviceId, format),
    );

    try {
      _mediaStream =
          await web.window.navigator.mediaDevices
              .getUserMedia(constraints)
              .toDart;

      _audioContext = web.AudioContext();

      // Ensure audio context is running
      if (_audioContext!.state == 'suspended') {
        await _audioContext!.resume().toDart;
      }

      _sourceNode = _audioContext!.createMediaStreamSource(_mediaStream!);
      _processorNode = _audioContext!.createScriptProcessor(
        format.numFrames,
        format.channels,
        format.channels,
      );

      _currentFormat = format;
    } catch (e) {
      throw Exception('Failed to configure audio: $e');
    }
  }

  JSAny _createAudioConstraints(String deviceId, MiniAVAudioInfo format) {
    final constraints = <String, dynamic>{
      'sampleRate': {'ideal': format.sampleRate},
      'channelCount': {'ideal': format.channels},
    };

    if (deviceId.isNotEmpty) {
      constraints['deviceId'] = {'exact': deviceId};
    }

    return constraints.jsify()!;
  }

  @override
  Future<MiniAVAudioInfo> getConfiguredFormat() async {
    if (_currentFormat == null) {
      throw StateError('Audio context not configured');
    }
    return _currentFormat!;
  }

  @override
  Future<void> startCapture(
    void Function(MiniAVBuffer buffer, Object? userData) onData, {
    Object? userData,
  }) async {
    if (_mediaStream == null ||
        _audioContext == null ||
        _sourceNode == null ||
        _processorNode == null) {
      throw StateError('Audio not configured');
    }

    await stopCapture(); // Clean up any previous capture

    _bufferController = StreamController<MiniAVBuffer>();
    _onData = onData;
    _userData = userData;

    // Set up the audio processing callback using JS interop
    _processorNode!.onaudioprocess = _createAudioProcessCallback();

    // Connect the audio processing chain
    _sourceNode!.connect(_processorNode!);
    _processorNode!.connect(_audioContext!.destination);
  }

  JSFunction _createAudioProcessCallback() {
    return (web.AudioProcessingEvent event) {
      _processAudioBuffer(event);
    }.toJS;
  }

  void _processAudioBuffer(web.AudioProcessingEvent event) {
    if (_onData == null) return;

    try {
      final inputBuffer = event.inputBuffer;
      final numChannels = inputBuffer.numberOfChannels;
      final frameCount = inputBuffer.length;

      // Interleave audio data if multiple channels
      final totalSamples = frameCount * numChannels;
      final interleavedData = Float32List(totalSamples);

      for (int channel = 0; channel < numChannels; channel++) {
        final channelData = inputBuffer.getChannelData(channel).toDart;
        for (int frame = 0; frame < frameCount; frame++) {
          interleavedData[frame * numChannels + channel] = channelData[frame];
        }
      }

      final audioInfo = MiniAVAudioInfo(
        format: MiniAVAudioFormat.f32,
        sampleRate: inputBuffer.sampleRate.toInt(),
        channels: numChannels,
        numFrames: frameCount,
      );

      final audioBuffer = MiniAVAudioBuffer(
        frameCount: frameCount,
        info: audioInfo,
        data: Uint8List.view(interleavedData.buffer),
      );

      final buffer = MiniAVBuffer(
        type: MiniAVBufferType.audio,
        contentType: MiniAVBufferContentType.cpu,
        timestampUs: _WebUtils._getCurrentTimestampUs(),
        data: audioBuffer,
        dataSizeBytes: interleavedData.lengthInBytes,
      );

      try {
        _onData!(buffer, _userData);
      } catch (e, s) {
        print('Error in audio user callback: $e\n$s');
      }
    } catch (e) {
      // Handle audio processing errors silently or log them
    }
  }

  @override
  Future<void> stopCapture() async {
    _processorNode?.disconnect();
    _sourceNode?.disconnect();

    // Clear the callback
    if (_processorNode != null) {
      _processorNode!.onaudioprocess = null;
    }

    _bufferController?.close();
    _bufferController = null;
    _onData = null;
    _userData = null;
  }

  @override
  Future<void> destroy() async {
    _mediaStream?.getTracks().toDart.forEach((track) => track.stop());
    _mediaStream = null;

    await _audioContext?.close().toDart;
    _audioContext = null;
    _sourceNode = null;
    _processorNode = null;
  }
}
