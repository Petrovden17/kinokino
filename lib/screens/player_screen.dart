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

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final uri = LegalSourceService().validateAuthorizedStream(widget.streamUrl);
      final controller = VideoPlayerController.networkUrl(uri);
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(false);
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _busy = false; });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      backgroundColor: Colors.black,
      body: Center(
        child: _busy ? const CircularProgressIndicator()
          : _error != null ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, style: const TextStyle(color: Colors.white)))
          : c == null ? const Text('Плеер недоступен')
          : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
              VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.all(18)),
              Wrap(alignment: WrapAlignment.center, spacing: 12, children: [
                IconButton(color: Colors.white, icon: const Icon(Icons.replay_10),
                  onPressed: () => c.seekTo(c.value.position - const Duration(seconds: 10))),
                IconButton(color: Colors.white, iconSize: 42,
                  icon: Icon(c.value.isPlaying ? Icons.pause_circle : Icons.play_circle),
                  onPressed: () => setState(() => c.value.isPlaying ? c.pause() : c.play())),
                IconButton(color: Colors.white, icon: const Icon(Icons.forward_10),
                  onPressed: () => c.seekTo(c.value.position + const Duration(seconds: 10))),
                PopupMenuButton<double>(
                  icon: const Icon(Icons.speed, color: Colors.white),
                  onSelected: c.setPlaybackSpeed,
                  itemBuilder: (_) => [0.75, 1.0, 1.25, 1.5, 2.0]
                    .map((v) => PopupMenuItem(value: v, child: Text('${v}x'))).toList(),
                ),
              ]),
            ]),
      ),
    );
  }
}
