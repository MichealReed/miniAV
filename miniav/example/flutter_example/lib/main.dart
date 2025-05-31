import 'package:flutter/material.dart';
import 'package:miniav/miniav.dart';
import 'dart:async';
import 'dart:math';

void main() {
  runApp(const MiniAVBenchmarkApp());
}

class MiniAVBenchmarkApp extends StatelessWidget {
  const MiniAVBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MiniAV Benchmark Dashboard',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
        cardTheme: CardThemeData(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const BenchmarkDashboard(),
    );
  }
}

class BenchmarkDashboard extends StatefulWidget {
  const BenchmarkDashboard({super.key});

  @override
  State<BenchmarkDashboard> createState() => _BenchmarkDashboardState();
}

class StreamConfiguration {
  String? selectedDeviceId;
  MiniAVDeviceInfo? selectedDevice;
  List<MiniAVDeviceInfo> availableDevices = [];
  dynamic selectedFormat; // MiniAVVideoInfo or MiniAVAudioInfo
  List<dynamic> availableFormats = [];
  bool isLoadingDevices = false;
  bool isLoadingFormats = false;
  String? error;

  void reset() {
    selectedDeviceId = null;
    selectedDevice = null;
    availableDevices.clear();
    selectedFormat = null;
    availableFormats.clear();
    error = null;
  }
}

class StreamStats {
  String name;
  String icon;
  int frameCount = 0;
  int totalBytes = 0;
  double avgLatency = 0.0;
  double currentFps = 0.0;
  double targetFps = 0.0;
  List<double> latencyHistory = [];
  List<double> fpsHistory = [];
  List<int> frameSizes = [];
  DateTime? lastFrameTime;
  DateTime startTime = DateTime.now();
  bool isActive = false;
  bool isStarting = false;
  bool isStopping = false;
  String deviceName = '';
  String resolution = '';
  double bandwidth = 0.0; // MB/s

  StreamStats(this.name, this.icon);

  void reset() {
    frameCount = 0;
    totalBytes = 0;
    avgLatency = 0.0;
    currentFps = 0.0;
    latencyHistory.clear();
    fpsHistory.clear();
    frameSizes.clear();
    lastFrameTime = null;
    startTime = DateTime.now();
    bandwidth = 0.0;
  }

  void addFrame(int bytes, int timestampUs) {
    final now = DateTime.now();
    frameCount++;
    totalBytes += bytes;
    frameSizes.add(bytes);

    // Calculate processing latency (time since last frame)
    double latency = 0.0;
    if (lastFrameTime != null) {
      latency = now.difference(lastFrameTime!).inMicroseconds / 1000.0; // ms
    }

    // Only add meaningful latency values (ignore first frame and outliers)
    if (latency > 0 && latency < 1000) {
      latencyHistory.add(latency);
    }

    // Calculate FPS
    if (lastFrameTime != null) {
      final timeDiff =
          now.difference(lastFrameTime!).inMicroseconds / 1000000.0;
      if (timeDiff > 0) {
        final instantFps = 1.0 / timeDiff;
        fpsHistory.add(instantFps);

        if (fpsHistory.length > 30) {
          fpsHistory.removeAt(0);
        }
        currentFps = fpsHistory.reduce((a, b) => a + b) / fpsHistory.length;
      }
    }

    // Rolling average of last 100 latency samples
    if (latencyHistory.length > 100) {
      latencyHistory.removeAt(0);
    }

    if (latencyHistory.isNotEmpty) {
      avgLatency =
          latencyHistory.reduce((a, b) => a + b) / latencyHistory.length;
    }

    // Keep only last 1000 frame sizes for memory efficiency
    if (frameSizes.length > 1000) {
      frameSizes.removeAt(0);
    }

    // Calculate bandwidth (MB/s)
    final elapsed = now.difference(startTime).inMicroseconds / 1000000.0;
    if (elapsed > 0) {
      bandwidth = (totalBytes / (1024 * 1024)) / elapsed;
    }

    lastFrameTime = now;
  }

  double get avgFrameSize =>
      frameSizes.isEmpty
          ? 0
          : frameSizes.reduce((a, b) => a + b) / frameSizes.length;
  double get fpsEfficiency =>
      targetFps > 0 ? (currentFps / targetFps) * 100 : 0;
  double get minLatency =>
      latencyHistory.isEmpty ? 0 : latencyHistory.reduce(min);
  double get maxLatency =>
      latencyHistory.isEmpty ? 0 : latencyHistory.reduce(max);
}

class _BenchmarkDashboardState extends State<BenchmarkDashboard> {
  final Map<String, StreamStats> _stats = {};
  final Map<String, dynamic> _contexts = {};
  final Map<String, StreamConfiguration> _configs = {};
  Timer? _uiUpdateTimer;
  bool _showConfig = false;

  @override
  void initState() {
    super.initState();
    MiniAV.setLogLevel(MiniAVLogLevel.warn);

    // Initialize stats and configs
    _stats['camera'] = StreamStats('Camera', '📹');
    _stats['screen'] = StreamStats('Screen', '🖥️');
    _stats['audioInput'] = StreamStats('Audio Input', '🎤');
    _stats['loopback'] = StreamStats('Loopback', '🔄');

    _configs['camera'] = StreamConfiguration();
    _configs['screen'] = StreamConfiguration();
    _configs['audioInput'] = StreamConfiguration();
    _configs['loopback'] = StreamConfiguration();

    // Load initial device lists
    _loadAllDevices();

    // Update UI every 100ms for smooth statistics
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiUpdateTimer?.cancel();
    _stopAllStreams();
    super.dispose();
  }

  Future<void> _loadAllDevices() async {
    await Future.wait([
      _loadDevices('camera'),
      _loadDevices('screen'),
      _loadDevices('audioInput'),
      _loadDevices('loopback'),
    ]);
  }

  Future<void> _loadDevices(String streamKey) async {
    final config = _configs[streamKey]!;

    setState(() {
      config.isLoadingDevices = true;
      config.error = null;
    });

    try {
      List<MiniAVDeviceInfo> devices;
      switch (streamKey) {
        case 'camera':
          devices = await MiniCamera.enumerateDevices();
          break;
        case 'screen':
          devices = await MiniScreen.enumerateDisplays();
          break;
        case 'audioInput':
          devices = await MiniAudioInput.enumerateDevices();
          break;
        case 'loopback':
          devices = await MiniLoopback.enumerateDevices();
          break;
        default:
          devices = [];
      }

      setState(() {
        config.availableDevices = devices;
        if (devices.isNotEmpty) {
          // Auto-select reasonable defaults
          if (streamKey == 'camera' && devices.length > 1) {
            config.selectedDevice = devices[1]; // Often the better camera
          } else if (streamKey == 'loopback' && devices.length > 4) {
            config.selectedDevice = devices[4]; // Often speakers
          } else {
            config.selectedDevice = devices.first;
          }
          config.selectedDeviceId = config.selectedDevice!.deviceId;

          // Load formats for selected device
          _loadFormats(streamKey);
        }
      });
    } catch (e) {
      setState(() {
        config.error = 'Failed to load devices: $e';
      });
    } finally {
      setState(() {
        config.isLoadingDevices = false;
      });
    }
  }

  Future<void> _loadFormats(String streamKey) async {
    final config = _configs[streamKey]!;
    if (config.selectedDeviceId == null) return;

    setState(() {
      config.isLoadingFormats = true;
    });

    try {
      List<dynamic> formats;
      switch (streamKey) {
        case 'camera':
          formats = await MiniCamera.getSupportedFormats(
            config.selectedDeviceId!,
          );
          break;
        case 'screen':
          final result = await MiniScreen.getDefaultFormats(
            config.selectedDeviceId!,
          );
          formats = [result.$1]; // Just video format for now
          break;
        case 'audioInput':
          final defaultFormat = await MiniAudioInput.getDefaultFormat(
            config.selectedDeviceId!,
          );
          formats = [defaultFormat]; // Just default for now
          break;
        case 'loopback':
          final defaultFormat = await MiniLoopback.getDefaultFormat(
            config.selectedDeviceId!,
          );
          formats = [defaultFormat]; // Just default for now
          break;
        default:
          formats = [];
      }

      setState(() {
        config.availableFormats = formats;
        if (formats.isNotEmpty) {
          config.selectedFormat = formats.first;
        }
      });
    } catch (e) {
      setState(() {
        config.error = 'Failed to load formats: $e';
      });
    } finally {
      setState(() {
        config.isLoadingFormats = false;
      });
    }
  }

  Future<void> _startAllStreams() async {
    await Future.wait([
      _toggleStream('camera'),
      _toggleStream('screen'),
      _toggleStream('audioInput'),
      _toggleStream('loopback'),
    ]);
  }

  Future<void> _stopAllStreams() async {
    final activeTasks = <Future>[];

    for (final key in _stats.keys) {
      if (_stats[key]!.isActive) {
        activeTasks.add(_toggleStream(key));
      }
    }

    await Future.wait(activeTasks);
  }

  Future<void> _toggleStream(String streamKey) async {
    final stats = _stats[streamKey]!;

    if (stats.isActive) {
      await _stopStream(streamKey);
    } else {
      await _startStream(streamKey);
    }
  }

  Future<void> _startStream(String streamKey) async {
    final stats = _stats[streamKey]!;
    final config = _configs[streamKey]!;

    if (config.selectedDevice == null || config.selectedFormat == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select device and format for $streamKey'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      stats.isStarting = true;
    });

    try {
      switch (streamKey) {
        case 'camera':
          await _setupCamera();
          break;
        case 'screen':
          await _setupScreen();
          break;
        case 'audioInput':
          await _setupAudioInput();
          break;
        case 'loopback':
          await _setupLoopback();
          break;
      }
    } catch (e) {
      print('Error starting $streamKey: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start $streamKey: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        stats.isStarting = false;
      });
    }
  }

  Future<void> _stopStream(String streamKey) async {
    final stats = _stats[streamKey]!;
    final context = _contexts[streamKey];

    if (context == null) return;

    setState(() {
      stats.isStopping = true;
    });

    try {
      if (context is MiniCameraContext) {
        await context.stopCapture();
        await context.destroy();
      } else if (context is MiniScreenContext) {
        await context.stopCapture();
        await context.destroy();
      } else if (context is MiniAudioInputContext) {
        await context.stopCapture();
        await context.destroy();
      } else if (context is MiniLoopbackContext) {
        await context.stopCapture();
        await context.destroy();
      }

      _contexts.remove(streamKey);
      stats.isActive = false;
    } catch (e) {
      print('Error stopping $streamKey: $e');
    } finally {
      setState(() {
        stats.isStopping = false;
      });
    }
  }

  Future<void> _setupCamera() async {
    final config = _configs['camera']!;
    final format = config.selectedFormat as MiniAVVideoInfo;

    final context = await MiniCamera.createContext();
    await context.configure(config.selectedDeviceId!, format);
    _contexts['camera'] = context;

    final stats = _stats['camera']!;
    stats.reset();
    stats.deviceName = config.selectedDevice!.name;
    stats.resolution = '${format.width}x${format.height}';
    stats.targetFps = format.frameRateNumerator / format.frameRateDenominator;
    stats.isActive = true;
    stats.startTime = DateTime.now();

    await context.startCapture((buffer, userData) {
      stats.addFrame(buffer.dataSizeBytes, buffer.timestampUs);
      MiniAV.releaseBuffer(buffer);
    });
  }

  Future<void> _setupScreen() async {
    final config = _configs['screen']!;
    final format = config.selectedFormat as MiniAVVideoInfo;

    final context = await MiniScreen.createContext();
    await context.configureDisplay(
      config.selectedDeviceId!,
      format,
      captureAudio: false,
    );
    _contexts['screen'] = context;

    final stats = _stats['screen']!;
    stats.reset();
    stats.deviceName = config.selectedDevice!.name;
    stats.resolution = '${format.width}x${format.height}';
    stats.targetFps = format.frameRateNumerator / format.frameRateDenominator;
    stats.isActive = true;
    stats.startTime = DateTime.now();

    await context.startCapture((buffer, userData) {
      if (buffer.type == MiniAVBufferType.video) {
        stats.addFrame(buffer.dataSizeBytes, buffer.timestampUs);
        MiniAV.releaseBuffer(buffer);
      }
    });
  }

  Future<void> _setupAudioInput() async {
    final config = _configs['audioInput']!;
    final format = config.selectedFormat as MiniAVAudioInfo;

    final context = await MiniAudioInput.createContext();
    await context.configure(config.selectedDeviceId!, format);
    _contexts['audioInput'] = context;

    final stats = _stats['audioInput']!;
    stats.reset();
    stats.deviceName = config.selectedDevice!.name;
    stats.resolution = '${format.channels}ch ${format.sampleRate}Hz';
    stats.targetFps = format.sampleRate / format.numFrames;
    stats.isActive = true;
    stats.startTime = DateTime.now();

    await context.startCapture((buffer, userData) {
      stats.addFrame(buffer.dataSizeBytes, buffer.timestampUs);
      MiniAV.releaseBuffer(buffer);
    });
  }

  Future<void> _setupLoopback() async {
    final config = _configs['loopback']!;
    final format = config.selectedFormat as MiniAVAudioInfo;

    final context = await MiniLoopback.createContext();
    await context.configure(config.selectedDeviceId!, format);
    _contexts['loopback'] = context;

    final stats = _stats['loopback']!;
    stats.reset();
    stats.deviceName = config.selectedDevice!.name;
    stats.resolution = '${format.channels}ch ${format.sampleRate}Hz';
    stats.targetFps = format.sampleRate / format.numFrames;
    stats.isActive = true;
    stats.startTime = DateTime.now();

    await context.startCapture((buffer, userData) {
      stats.addFrame(buffer.dataSizeBytes, buffer.timestampUs);
      // Note: Not releasing loopback buffers as per original example
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeStreams = _stats.values.where((s) => s.isActive).length;
    final hasActiveStreams = activeStreams > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🎥 MiniAV Benchmark Dashboard'),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => setState(() => _showConfig = !_showConfig),
            icon: Icon(_showConfig ? Icons.settings_outlined : Icons.settings),
            tooltip: _showConfig ? 'Hide Configuration' : 'Show Configuration',
          ),
          if (hasActiveStreams)
            IconButton(
              onPressed: _stopAllStreams,
              icon: const Icon(Icons.stop),
              tooltip: 'Stop All Streams',
            ),
          if (!hasActiveStreams)
            IconButton(
              onPressed: _startAllStreams,
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Start All Streams',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Configuration Panel
            if (_showConfig) ...[
              _buildConfigurationPanel(),
              const SizedBox(height: 16),
            ],

            // Overall System Stats
            _buildSystemStatsCard(),
            const SizedBox(height: 16),

            // Individual Stream Stats with Controls
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.75,
                ),
                itemCount: _stats.length,
                itemBuilder: (context, index) {
                  final entry = _stats.entries.elementAt(index);
                  final streamKey = entry.key;
                  final stats = entry.value;
                  return _buildStreamStatsCard(streamKey, stats);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigurationPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.settings, size: 20),
                SizedBox(width: 8),
                Text(
                  'Stream Configuration',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _configs.length,
                itemBuilder: (context, index) {
                  final entry = _configs.entries.elementAt(index);
                  final streamKey = entry.key;
                  final config = entry.value;
                  final stats = _stats[streamKey]!;

                  return Container(
                    width: 280,
                    margin: const EdgeInsets.only(right: 16),
                    child: _buildStreamConfigCard(streamKey, stats, config),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamConfigCard(
    String streamKey,
    StreamStats stats,
    StreamConfiguration config,
  ) {
    return Card(
      color: Theme.of(context).colorScheme.surface.withOpacity(0.7),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(stats.icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text(
                  stats.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Device Selection
            Text(
              'Device:',
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
            if (config.isLoadingDevices)
              const LinearProgressIndicator(minHeight: 2)
            else if (config.availableDevices.isEmpty)
              Text(
                'No devices',
                style: TextStyle(fontSize: 10, color: Colors.red[300]),
              )
            else
              DropdownButton<String>(
                isExpanded: true,
                value: config.selectedDeviceId,
                style: const TextStyle(fontSize: 10),
                items:
                    config.availableDevices.map((device) {
                      return DropdownMenuItem<String>(
                        value: device.deviceId,
                        child: Text(
                          device.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    }).toList(),
                onChanged:
                    stats.isActive
                        ? null
                        : (value) {
                          setState(() {
                            config.selectedDeviceId = value;
                            config.selectedDevice = config.availableDevices
                                .firstWhere((d) => d.deviceId == value);
                          });
                          _loadFormats(streamKey);
                        },
              ),

            const SizedBox(height: 8),

            // Format Selection
            Text(
              'Format:',
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
            if (config.isLoadingFormats)
              const LinearProgressIndicator(minHeight: 2)
            else if (config.availableFormats.isEmpty)
              Text(
                'No formats',
                style: TextStyle(fontSize: 10, color: Colors.red[300]),
              )
            else
              DropdownButton<dynamic>(
                isExpanded: true,
                value: config.selectedFormat,
                style: const TextStyle(fontSize: 10),
                items:
                    config.availableFormats.map((format) {
                      String displayText;
                      if (format is MiniAVVideoInfo) {
                        final fps =
                            format.frameRateNumerator /
                            format.frameRateDenominator;
                        displayText =
                            '${format.width}x${format.height} @${fps.toStringAsFixed(0)}fps';
                      } else if (format is MiniAVAudioInfo) {
                        displayText =
                            '${format.channels}ch ${format.sampleRate}Hz';
                      } else {
                        displayText = format.toString();
                      }

                      return DropdownMenuItem<dynamic>(
                        value: format,
                        child: Text(
                          displayText,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    }).toList(),
                onChanged:
                    stats.isActive
                        ? null
                        : (value) {
                          setState(() {
                            config.selectedFormat = value;
                          });
                        },
              ),

            // Error Display
            if (config.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  config.error!,
                  style: TextStyle(fontSize: 9, color: Colors.red[300]),
                ),
              ),

            // Refresh Button
            const Spacer(),
            TextButton.icon(
              onPressed: stats.isActive ? null : () => _loadDevices(streamKey),
              icon: const Icon(Icons.refresh, size: 12),
              label: const Text('Refresh', style: TextStyle(fontSize: 10)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemStatsCard() {
    final totalFrames = _stats.values.fold(
      0,
      (sum, stats) => sum + stats.frameCount,
    );
    final totalBandwidth = _stats.values.fold(
      0.0,
      (sum, stats) => sum + stats.bandwidth,
    );
    final activeStreams = _stats.values.where((stats) => stats.isActive).length;
    final avgLatency =
        _stats.values
            .where((s) => s.isActive && s.latencyHistory.isNotEmpty)
            .fold(0.0, (sum, stats) => sum + stats.avgLatency) /
        max(1, activeStreams);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'System Overview',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: activeStreams > 0 ? Colors.green : Colors.grey,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    activeStreams > 0 ? 'LIVE ($activeStreams)' : 'STOPPED',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Active Streams',
                  '$activeStreams/4',
                  Icons.stream,
                ),
                _buildStatItem(
                  'Total Frames',
                  _formatNumber(totalFrames),
                  Icons.video_library,
                ),
                _buildStatItem(
                  'Total Bandwidth',
                  '${totalBandwidth.toStringAsFixed(1)} MB/s',
                  Icons.speed,
                ),
                _buildStatItem(
                  'Avg Latency',
                  '${avgLatency.toStringAsFixed(1)} ms',
                  Icons.timer,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamStatsCard(String streamKey, StreamStats stats) {
    final config = _configs[streamKey]!;
    final efficiency = stats.fpsEfficiency;
    final efficiencyColor =
        efficiency > 90
            ? Colors.green
            : efficiency > 70
            ? Colors.orange
            : Colors.red;

    final isLoading = stats.isStarting || stats.isStopping;
    final canStart =
        config.selectedDevice != null && config.selectedFormat != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Controls
            Row(
              children: [
                Text(stats.icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stats.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      if (stats.deviceName.isNotEmpty)
                        Text(
                          stats.deviceName,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.grey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Start/Stop Button
                SizedBox(
                  width: 32,
                  height: 32,
                  child:
                      isLoading
                          ? const Padding(
                            padding: EdgeInsets.all(6.0),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : IconButton(
                            padding: EdgeInsets.zero,
                            onPressed:
                                canStart
                                    ? () => _toggleStream(streamKey)
                                    : null,
                            icon: Icon(
                              stats.isActive ? Icons.stop : Icons.play_arrow,
                              size: 16,
                              color:
                                  stats.isActive
                                      ? Colors.red
                                      : canStart
                                      ? Colors.green
                                      : Colors.grey,
                            ),
                            tooltip:
                                stats.isActive
                                    ? 'Stop ${stats.name}'
                                    : canStart
                                    ? 'Start ${stats.name}'
                                    : 'Configure device/format first',
                          ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Status Indicator
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                color:
                    stats.isActive
                        ? Colors.green.withOpacity(0.2)
                        : isLoading
                        ? Colors.orange.withOpacity(0.2)
                        : canStart
                        ? Colors.grey.withOpacity(0.2)
                        : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      stats.isActive
                          ? Colors.green
                          : isLoading
                          ? Colors.orange
                          : canStart
                          ? Colors.grey
                          : Colors.red,
                  width: 1,
                ),
              ),
              child: Text(
                stats.isActive
                    ? 'ACTIVE'
                    : stats.isStarting
                    ? 'STARTING...'
                    : stats.isStopping
                    ? 'STOPPING...'
                    : canStart
                    ? 'READY'
                    : 'NOT CONFIGURED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color:
                      stats.isActive
                          ? Colors.green
                          : isLoading
                          ? Colors.orange
                          : canStart
                          ? Colors.grey
                          : Colors.red,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),

            // Key Metrics
            Expanded(
              child: Column(
                children: [
                  _buildMetricRow(
                    'FPS',
                    '${stats.currentFps.toStringAsFixed(1)}/${stats.targetFps.toStringAsFixed(0)}',
                  ),
                  _buildMetricRow(
                    'Efficiency',
                    '${efficiency.toStringAsFixed(0)}%',
                    color: efficiencyColor,
                  ),
                  _buildMetricRow(
                    'Latency',
                    '${stats.avgLatency.toStringAsFixed(1)} ms',
                  ),
                  _buildMetricRow('Frames', _formatNumber(stats.frameCount)),
                  _buildMetricRow(
                    'Bandwidth',
                    '${stats.bandwidth.toStringAsFixed(1)} MB/s',
                  ),
                  _buildMetricRow(
                    'Avg Size',
                    _formatBytes(stats.avgFrameSize.round()),
                  ),
                  if (stats.resolution.isNotEmpty)
                    _buildMetricRow('Resolution', stats.resolution),
                ],
              ),
            ),

            // Latency Range
            if (stats.latencyHistory.isNotEmpty) ...[
              const Divider(height: 8),
              Text(
                'Range: ${stats.minLatency.toStringAsFixed(1)}-${stats.maxLatency.toStringAsFixed(1)} ms',
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.cyan),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildMetricRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int number) {
    if (number < 1000) return number.toString();
    if (number < 1000000) return '${(number / 1000).toStringAsFixed(1)}K';
    return '${(number / 1000000).toStringAsFixed(1)}M';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
