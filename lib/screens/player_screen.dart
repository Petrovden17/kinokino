import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../services/legal_source_service.dart';
import '../services/internet_archive_service.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.streamUrl, required this.title, this.variants = const []});
  final String streamUrl;
  final String title;
  final List<ArchiveVideoVariant> variants;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  String? _error;
  bool _busy = true;
  bool _fullscreen = false;
  double _speed = 1;
  late String _activeUrl;

  @override
  void initState() {
    super.initState();
    _activeUrl = widget.streamUrl;
    _initialize();
  }

  Future<void> _initialize() async {
    if (mounted) setState(() { _busy = true; _error = null; });
    VideoPlayerController? next;
    try {
      final uri = LegalSourceService().validateAuthorizedStream(_activeUrl);
      next = VideoPlayerController.networkUrl(uri);
      _controller = next;
      next.addListener(_onChanged);
      await next.initialize();
      await next.setLooping(false);
      if (!mounted) return;
      setState(() => _busy = false);
      await next.play();
    } catch (e) {
      next?.removeListener(_onChanged);
      await next?.dispose();
      if (identical(_controller, next)) _controller = null;
      if (mounted) setState(() { _error = _friendlyError(e); _busy = false; });
    }
  }

  void _onChanged() {
    if (!mounted) return;
    final value = _controller?.value;
    if (value?.hasError == true) {
      setState(() => _error = value?.errorDescription ?? 'Ошибка воспроизведения');
    } else {
      setState(() {});
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('HTTPS')) return message;
    return 'Не удалось воспроизвести этот видеофайл. Формат или кодек может не поддерживаться Windows.\n\n$message';
  }

  String _time(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Future<void> _seek(Duration offset) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final duration = c.value.duration;
    final target = c.value.position + offset;
    await c.seekTo(target < Duration.zero ? Duration.zero : target > duration ? duration : target);
  }

  Future<void> _selectQuality(ArchiveVideoVariant variant) async {
    if (variant.url.toString() == _activeUrl) return;
    final wasPlaying = _controller?.value.isPlaying ?? false;
    final previous = _controller;
    previous?.removeListener(_onChanged);
    _controller = null;
    await previous?.dispose();
    if (!mounted) return;
    setState(() {
      _activeUrl = variant.url.toString();
      _busy = true;
      _error = null;
    });
    await _initialize();
    if (wasPlaying && _controller?.value.isInitialized == true) {
      await _controller!.play();
    }
  }

  Future<void> _toggleFullscreen() async {
    final entering = !_fullscreen;
    if (entering) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    if (mounted) setState(() => _fullscreen = entering);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _controller?.removeListener(_onChanged);
    _controller?.dispose();
    super.dispose();
  }

  Widget _control(IconData icon, String tooltip, VoidCallback? action, {double size = 34}) {
    return IconButton(
      tooltip: tooltip,
      onPressed: action,
      iconSize: size,
      color: Colors.white,
      style: IconButton.styleFrom(backgroundColor: Colors.black54),
      icon: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final value = c?.value;
    final ready = value?.isInitialized == true;
    final duration = ready ? value!.duration : Duration.zero;
    final position = ready ? value!.position : Duration.zero;
    final totalMs = duration.inMilliseconds;
    final currentMs = totalMs <= 0 ? 0.0 : position.inMilliseconds.clamp(0, totalMs).toDouble();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _fullscreen ? null : AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.black,
      ),
      body: SafeArea(
        child: _busy
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(), SizedBox(height: 14),
              Text('Загружаем видео…'),
            ]))
          : _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
                mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, color: Colors.orange, size: 52),
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(onPressed: _initialize, icon: const Icon(Icons.refresh), label: const Text('Повторить')),
                ],
              )))
            : !ready || c == null
              ? const Center(child: Text('Плеер не инициализирован'))
              : LayoutBuilder(builder: (context, constraints) {
                  final v = c.value;
                  final wide = constraints.maxWidth > 700;
                  return Center(child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Expanded(child: Center(child: AspectRatio(
                        aspectRatio: v.aspectRatio > 0 ? v.aspectRatio : 16 / 9,
                        child: Stack(fit: StackFit.expand, alignment: Alignment.center, children: [
                          VideoPlayer(c),
                          if (v.isBuffering)
                            const Center(child: CircularProgressIndicator()),
                          if (v.isPlaying)
                            Align(alignment: Alignment.center, child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _control(Icons.replay_10, 'Назад на 10 секунд', () => _seek(const Duration(seconds: -10)), size: wide ? 44 : 34),
                                const SizedBox(width: 20),
                                _control(Icons.pause_circle_filled, 'Пауза', c.pause, size: wide ? 64 : 52),
                                const SizedBox(width: 20),
                                _control(Icons.forward_10, 'Вперёд на 10 секунд', () => _seek(const Duration(seconds: 10)), size: wide ? 44 : 34),
                              ],
                            ))
                          else
                            Center(child: _control(Icons.play_circle_fill, 'Воспроизвести', c.play, size: 68)),
                        ]),
                      ))),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 12, vertical: 8),
                        child: Column(children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                            ),
                            child: Slider(
                              min: 0,
                              max: totalMs > 0 ? totalMs.toDouble() : 1,
                              value: totalMs > 0 ? currentMs : 0,
                              onChanged: totalMs <= 0 ? null : (v) => c.seekTo(Duration(milliseconds: v.round())),
                            ),
                          ),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text(_time(position), style: const TextStyle(color: Colors.white70)),
                            Text(_time(duration), style: const TextStyle(color: Colors.white70)),
                          ]),
                          const SizedBox(height: 4),
                          Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, children: [
                            _control(Icons.replay_10, 'Назад 10 секунд', () => _seek(const Duration(seconds: -10)), size: 30),
                            _control(v.isPlaying ? Icons.pause : Icons.play_arrow,
                              v.isPlaying ? 'Пауза' : 'Воспроизвести',
                              () => v.isPlaying ? c.pause() : c.play(), size: 42),
                            _control(Icons.forward_10, 'Вперёд 10 секунд', () => _seek(const Duration(seconds: 10)), size: 30),
                            if (widget.variants.length > 1)
                              PopupMenuButton<ArchiveVideoVariant>(
                                tooltip: 'Качество видео',
                                onSelected: _selectQuality,
                                itemBuilder: (_) => widget.variants.map((variant) =>
                                  PopupMenuItem(
                                    value: variant,
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.hd_outlined, size: 18),
                                      const SizedBox(width: 8),
                                      Text(variant.label),
                                      if (variant.url.toString() == _activeUrl) ...[
                                        const SizedBox(width: 10), const Icon(Icons.check, size: 16),
                                      ],
                                    ]),
                                  )).toList(),
                                child: Padding(padding: const EdgeInsets.all(10), child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.hd_outlined),
                                    const SizedBox(width: 4),
                                    Text(widget.variants.firstWhere(
                                      (v) => v.url.toString() == _activeUrl,
                                      orElse: () => widget.variants.first,
                                    ).label),
                                  ],
                                )),
                              ),
                            PopupMenuButton<double>(
                              tooltip: 'Скорость',
                              initialValue: _speed,
                              onSelected: (v) async { await c.setPlaybackSpeed(v); if (mounted) setState(() => _speed = v); },
                              itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                                .map((v) => PopupMenuItem(value: v, child: Text('${v}×'))).toList(),
                              child: Padding(padding: const EdgeInsets.all(10), child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.speed), const SizedBox(width: 4), Text('${_speed}×'),
                              ])),
                            ),
                            IconButton(
                              tooltip: 'Громкость',
                              onPressed: () => c.setVolume(v.volume > 0 ? 0 : 1),
                              icon: Icon(v.volume > 0 ? Icons.volume_up : Icons.volume_off),
                            ),
                            IconButton(
                              tooltip: _fullscreen ? 'Обычный режим' : 'Полный экран',
                              onPressed: _toggleFullscreen,
                              icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                            ),
                          ]),
                        ]),
                      ),
                    ]),
                  ));
                }),
      ),
    );
  }
}
