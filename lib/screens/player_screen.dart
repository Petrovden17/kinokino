import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/legal_source_service.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.streamUrl, required this.title});
  final String streamUrl;
  final String title;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  String? _error;
  bool _busy = true;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (mounted) setState(() { _busy = true; _error = null; });
    VideoPlayerController? controller;
    try {
      final uri = LegalSourceService().validateAuthorizedStream(widget.streamUrl);
      controller = VideoPlayerController.networkUrl(uri);
      _controller = controller;
      controller.addListener(_onPlayerChanged);
      await controller.initialize();
      await controller.setLooping(false);
      if (!mounted) return;
      setState(() => _busy = false);
      await controller.play();
    } catch (e) {
      controller?.removeListener(_onPlayerChanged);
      await controller?.dispose();
      if (identical(_controller, controller)) _controller = null;
      if (mounted) setState(() { _error = _friendlyError(e); _busy = false; });
    }
  }

  void _onPlayerChanged() {
    if (!mounted) return;
    final value = _controller?.value;
    if (value != null && value.hasError && _error == null) {
      setState(() => _error = value.errorDescription ?? 'Не удалось воспроизвести видео.');
    } else {
      setState(() {});
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('HTTPS')) return message;
    return 'Не удалось открыть видео. Проверь подключение и доступность легального видеопотока.\n\n$message';
  }

  String _time(Duration duration) {
    String two(int value) => value.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '${two(minutes)}:${two(seconds)}';
  }

  Future<void> _seekBy(int seconds) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final target = c.value.position + Duration(seconds: seconds);
    final duration = c.value.duration;
    await c.seekTo(target < Duration.zero ? Duration.zero : (target > duration ? duration : target));
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlayerChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final value = c?.value;
    final ready = value?.isInitialized == true;
    final duration = ready ? value!.duration : Duration.zero;
    final position = ready ? value!.position : Duration.zero;

    return Scaffold(
      backgroundColor: const Color(0xFF05080E),
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: const Color(0xFF05080E),
      ),
      body: Center(
        child: _busy
            ? const Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Подключаемся к видеопотоку…', style: TextStyle(color: Colors.white70)),
              ])
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline, color: Colors.orangeAccent, size: 52),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _initialize,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Повторить'),
                      ),
                    ]),
                  )
                : c == null || !ready
                    ? const Text('Плеер недоступен', style: TextStyle(color: Colors.white))
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AspectRatio(
                              aspectRatio: value!.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  VideoPlayer(c),
                                  if (value.isBuffering)
                                    const CircularProgressIndicator(),
                                  if (value.hasError)
                                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 42),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            VideoProgressIndicator(
                              c,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: Color(0xFF6C8CFF),
                                bufferedColor: Colors.white38,
                                backgroundColor: Colors.white12,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_time(position), style: const TextStyle(color: Colors.white70, fontFeatures: [])),
                                Text(_time(duration), style: const TextStyle(color: Colors.white70)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 22,
                              children: [
                                IconButton(
                                  tooltip: 'Назад на 10 секунд',
                                  color: Colors.white,
                                  iconSize: 30,
                                  onPressed: () => _seekBy(-10),
                                  icon: const Icon(Icons.replay_10),
                                ),
                                IconButton.filled(
                                  tooltip: value.isPlaying ? 'Пауза' : 'Воспроизвести',
                                  iconSize: 38,
                                  onPressed: () => value.isPlaying ? c.pause() : c.play(),
                                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                                ),
                                IconButton(
                                  tooltip: 'Вперёд на 10 секунд',
                                  color: Colors.white,
                                  iconSize: 30,
                                  onPressed: () => _seekBy(10),
                                  icon: const Icon(Icons.forward_10),
                                ),
                                PopupMenuButton<double>(
                                  tooltip: 'Скорость воспроизведения',
                                  initialValue: _speed,
                                  icon: const Icon(Icons.speed, color: Colors.white),
                                  onSelected: (speed) async {
                                    await c.setPlaybackSpeed(speed);
                                    if (mounted) setState(() => _speed = speed);
                                  },
                                  itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                                      .map((speed) => PopupMenuItem(
                                            value: speed,
                                            child: Text(speed == 1.0 ? 'Обычная (1×)' : '${speed}×'),
                                          ))
                                      .toList(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Воспроизводятся только доступные вам легальные видеопотоки.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
      ),
    );
  }
}
