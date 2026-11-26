import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:window_manager/window_manager.dart';
import 'package:video_player/video_player.dart';
import '../services/legal_source_service.dart';
import '../services/internet_archive_service.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.streamUrl, required this.title, this.variants = const [], this.preferredVideoQuality = 'auto', this.onChooseEpisode, this.onResolveEpisode, this.onResolveAudio});
  final String streamUrl;
  final String title;
  final List<ArchiveVideoVariant> variants;
  final String preferredVideoQuality;
  final Future<Map<String, dynamic>?> Function()? onChooseEpisode;
  final Future<ArchiveVideo?> Function(Map<String, dynamic>)? onResolveEpisode;
  final Future<ArchiveVideo?> Function(String language)? onResolveAudio;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  String? _error;
  bool _busy = true;
  bool _fullscreen = false;
  double _speed = 1;
  bool _controlsVisible = true;
  BoxFit _videoFit = BoxFit.contain;
  Timer? _controlsTimer;
  late String _activeUrl;
  late String _activeTitle;
  late List<ArchiveVideoVariant> _activeVariants;
  String _activeAudioLanguage = 'auto';
  bool _changingAudio = false;

  ArchiveVideoVariant? _preferredVariant(List<ArchiveVideoVariant> variants, String preference) {
    if (variants.isEmpty || preference == 'auto') return null;
    final limit = int.tryParse(preference);
    if (limit == null) return null;
    final underLimit = variants.where((v) => v.height > 0 && v.height <= limit).toList()
      ..sort((a, b) => b.height.compareTo(a.height));
    if (underLimit.isNotEmpty) return underLimit.first;
    final available = variants.where((v) => v.height > 0).toList()
      ..sort((a, b) => a.height.compareTo(b.height));
    return available.isEmpty ? null : available.first;
  }

  @override
  void initState() {
    super.initState();
    _activeVariants = widget.variants;
    _activeUrl = _preferredVariant(_activeVariants, widget.preferredVideoQuality)?.url.toString() ?? widget.streamUrl;
    _activeTitle = widget.title;
    _initialize();
    _scheduleControlsHide();
  }

  Future<void> _initialize({bool autoplay = true}) async {
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
      if (autoplay) {
        await next.play();
        _scheduleControlsHide();
      }
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
      setState(() => _error = 'Не удалось воспроизвести видео во встроенном плеере.');
    } else {
      setState(() {});
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('https')) {
      return 'Источник видео не прошёл проверку безопасности.';
    }
    return 'Не удалось запустить видео в этом плеере. Возможно, Windows не поддерживает его формат или кодек.';
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
    await _initialize(autoplay: wasPlaying);
  }

  Future<void> _selectAudioLanguage(String language) async {
    final resolve = widget.onResolveAudio;
    if (resolve == null || language == _activeAudioLanguage || _changingAudio) return;
    setState(() => _changingAudio = true);
    try {
      final source = await resolve(language);
      if (!mounted) return;
      if (source == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Версия с выбранной озвучкой не найдена.')));
        return;
      }
      final wasPlaying = _controller?.value.isPlaying ?? true;
      final previous = _controller;
      previous?.removeListener(_onChanged);
      _controller = null;
      await previous?.dispose();
      if (!mounted) return;
      setState(() {
        _activeVariants = source.variants;
        _activeUrl = _preferredVariant(source.variants, widget.preferredVideoQuality)?.url.toString() ?? source.url.toString();
        _activeAudioLanguage = language;
        _busy = true;
        _error = null;
      });
      await _initialize(autoplay: wasPlaying);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось переключить озвучку.')));
    } finally {
      if (mounted) setState(() => _changingAudio = false);
    }
  }
  Future<void> _selectEpisode() async {
    final choose = widget.onChooseEpisode;
    final resolve = widget.onResolveEpisode;
    if (choose == null || resolve == null) return;
    final episode = await choose();
    if (episode == null || !mounted) return;
    setState(() { _busy = true; _error = null; });
    final source = await resolve(episode);
    if (!mounted) return;
    if (source == null) {
      setState(() => _busy = false);
      return;
    }
    final wasPlaying = _controller?.value.isPlaying ?? true;
    final previous = _controller;
    previous?.removeListener(_onChanged);
    _controller = null;
    await previous?.dispose();
    if (!mounted) return;
    final season = (episode['season_number'] as num?)?.toInt() ?? 1;
    final number = (episode['episode_number'] as num?)?.toInt() ?? 1;
    final episodeName = (episode['name'] ?? 'Серия $number').toString();
    setState(() {
      _activeVariants = source.variants;
      _activeUrl = _preferredVariant(source.variants, widget.preferredVideoQuality)?.url.toString() ?? source.url.toString();
      _activeTitle = '${widget.title} · S${season.toString().padLeft(2, '0')}E${number.toString().padLeft(2, '0')} — $episodeName';
      _busy = true;
      _error = null;
    });
    await _initialize(autoplay: wasPlaying);
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    if (!_controlsVisible || _controller?.value.isPlaying != true) return;
    _controlsTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted && _controller?.value.isPlaying == true) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _revealControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleControlsHide();
  }

  Future<void> _exitFullscreen() async {
    if (!_fullscreen) return;
    await windowManager.setFullScreen(false);
    if (mounted) {
      setState(() {
        _fullscreen = false;
        _controlsVisible = true;
      });
      _scheduleControlsHide();
    }
  }

  Future<void> _toggleFullscreen() async {
    final entering = !_fullscreen;
    if (entering) {
      await windowManager.setFullScreen(true);
    } else {
      await windowManager.setFullScreen(false);
    }
    if (mounted) {
      setState(() {
        _fullscreen = entering;
        _controlsVisible = true;
      });
      _scheduleControlsHide();
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    if (_fullscreen) windowManager.setFullScreen(false);
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
    final wide = MediaQuery.sizeOf(context).width > 700;

    Widget controlBar() => Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _control(Icons.replay_10, 'Назад 10 секунд', () => _seek(const Duration(seconds: -10)), size: wide ? 34 : 28),
        _control(value?.isPlaying == true ? Icons.pause : Icons.play_arrow,
          value?.isPlaying == true ? 'Пауза' : 'Воспроизвести',
          () async {
            if (value?.isPlaying == true) {
              await c?.pause();
              _revealControls();
            } else {
              await c?.play();
              _revealControls();
            }
          }, size: wide ? 46 : 38),
        _control(Icons.forward_10, 'Вперёд 10 секунд', () => _seek(const Duration(seconds: 10)), size: wide ? 34 : 28),
        PopupMenuButton<BoxFit>(
          tooltip: 'Размер изображения',
          initialValue: _videoFit,
          onSelected: (fit) => setState(() => _videoFit = fit),
          itemBuilder: (_) => const [
            PopupMenuItem(value: BoxFit.contain, child: Text('Вписать целиком')),
            PopupMenuItem(value: BoxFit.cover, child: Text('Заполнить экран')),
            PopupMenuItem(value: BoxFit.fill, child: Text('Растянуть')),
          ],
          child: const Padding(
            padding: EdgeInsets.all(9),
            child: Icon(Icons.fit_screen, color: Colors.white),
          ),
        ),
        if (widget.onResolveAudio != null)
          PopupMenuButton<String>(
            tooltip: 'Озвучка / язык версии',
            onSelected: _selectAudioLanguage,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'auto', child: Text('Автоматически')) ,
              PopupMenuItem(value: 'ru', child: Text('Русская версия')) ,
              PopupMenuItem(value: 'original', child: Text('Оригинальная версия')) ,
            ],
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: _changingAudio
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.record_voice_over_outlined, color: Colors.white),
            ),
          ),
        if (_activeVariants.isNotEmpty)
          PopupMenuButton<ArchiveVideoVariant>(
            tooltip: 'Качество видео',
            onSelected: _selectQuality,
            itemBuilder: (_) => _activeVariants.map((variant) => PopupMenuItem(
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
            child: const Padding(
              padding: EdgeInsets.all(9),
              child: Icon(Icons.hd_outlined, color: Colors.white),
            ),
          ),
        if (widget.onChooseEpisode != null && widget.onResolveEpisode != null)
          IconButton(
            tooltip: 'Выбрать сезон и серию',
            onPressed: _selectEpisode,
            color: Colors.white,
            icon: const Icon(Icons.video_library_outlined),
          ),
        PopupMenuButton<double>(
          tooltip: 'Скорость',
          initialValue: _speed,
          onSelected: (speed) async {
            await c?.setPlaybackSpeed(speed);
            if (mounted) setState(() => _speed = speed);
          },
          itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
            .map((speed) => PopupMenuItem(value: speed, child: Text('${speed}×'))).toList(),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Text('${_speed}×', style: const TextStyle(color: Colors.white)),
          ),
        ),
        IconButton(
          tooltip: 'Громкость',
          color: Colors.white,
          onPressed: () => c?.setVolume((value?.volume ?? 1) > 0 ? 0 : 1),
          icon: Icon((value?.volume ?? 1) > 0 ? Icons.volume_up : Icons.volume_off),
        ),
        IconButton(
          tooltip: _fullscreen ? 'Выйти из полного экрана' : 'Полный экран',
          color: Colors.white,
          onPressed: _toggleFullscreen,
          icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
        ),
        if (_fullscreen)
          IconButton(
            tooltip: 'Закрыть плеер',
            color: Colors.white,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
      ],
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _exitFullscreen,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: _fullscreen ? null : AppBar(
            title: Text(_activeTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                      const SizedBox(height: 8),
                    ],
                  )))
                : !ready || c == null
                  ? const Center(child: Text('Плеер не инициализирован'))
                  : MouseRegion(
                      onHover: (_) => _revealControls(),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _revealControls,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Center(
                              child: FittedBox(
                                fit: _videoFit,
                                child: SizedBox(
                                  width: value!.size.width > 0 ? value.size.width : 1280,
                                  height: value.size.height > 0 ? value.size.height : 720,
                                  child: VideoPlayer(c),
                                ),
                              ),
                            ),
                            if (value.isBuffering)
                              const Center(child: CircularProgressIndicator()),
                            if (_controlsVisible) ...[
                              Positioned(
                                left: 0, right: 0, top: 0,
                                child: DecoratedBox(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                      colors: [Colors.black87, Colors.transparent]),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                                    child: Row(children: [
                                      Expanded(child: Text(_activeTitle,
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontSize: 16))),
                                      if (_fullscreen)
                                        IconButton(
                                          tooltip: 'Выйти из полного экрана',
                                          onPressed: _exitFullscreen,
                                          color: Colors.white,
                                          icon: const Icon(Icons.fullscreen_exit),
                                        ),
                                      IconButton(
                                        tooltip: 'Закрыть плеер',
                                        onPressed: () => Navigator.of(context).maybePop(),
                                        color: Colors.white,
                                        icon: const Icon(Icons.close),
                                      ),
                                    ]),
                                  ),
                                ),
                              ),
                              if (!value.isPlaying)
                                Center(child: _control(Icons.play_circle_fill, 'Воспроизвести', () {
                                  c.play();
                                  _revealControls();
                                }, size: 72)),
                              Positioned(
                                left: 0, right: 0, bottom: 0,
                                child: DecoratedBox(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                                      colors: [Colors.black87, Colors.transparent]),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                                    child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                                          onChanged: totalMs <= 0 ? null : (ms) {
                                            c.seekTo(Duration(milliseconds: ms.round()));
                                            _revealControls();
                                          },
                                        ),
                                      ),
                                      Row(children: [
                                        Text(_time(position), style: const TextStyle(color: Colors.white70)),
                                        const Spacer(),
                                        Flexible(child: controlBar()),
                                        const Spacer(),
                                        Text(_time(duration), style: const TextStyle(color: Colors.white70)),
                                      ]),
                                    ]),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
          ),
        ),
      ),
    );
  }
}
