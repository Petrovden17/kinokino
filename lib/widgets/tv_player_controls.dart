import 'package:flutter/material.dart';

class TvPlayerControls extends StatelessWidget {
  const TvPlayerControls({
    super.key,
    required this.onBack,
    required this.onPlayPause,
    required this.onSeekBack,
    required this.onSeekForward,
    required this.onSpeed,
    required this.onSubtitles,
    required this.speed,
    required this.playing,
  });

  final VoidCallback onBack;
  final VoidCallback onPlayPause;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;
  final VoidCallback onSpeed;
  final VoidCallback onSubtitles;
  final double speed;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: const Color(0xE6202633),
      foregroundColor: Colors.white,
      minimumSize: const Size(64, 58),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0x55FFFFFF)),
      ),
    );
    Widget control({
      required String label,
      required IconData icon,
      required VoidCallback action,
      bool primary = false,
    }) => FilledButton.icon(
      onPressed: action,
      style: style.copyWith(
        backgroundColor: WidgetStatePropertyAll(
          primary ? const Color(0xFFFFD21F) : const Color(0xE6202633),
        ),
        foregroundColor: WidgetStatePropertyAll(
          primary ? Colors.black : Colors.white,
        ),
      ),
      icon: Icon(icon, size: 23),
      label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 0, 30, 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xE9000000), Color(0x99000000), Colors.transparent],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 30, 18, 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    control(label: 'Назад', icon: Icons.arrow_back, action: onBack),
                    control(label: '−10 сек', icon: Icons.replay_10, action: onSeekBack),
                    control(
                      label: playing ? 'Пауза' : 'Играть',
                      icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      action: onPlayPause,
                      primary: true,
                    ),
                    control(label: '+10 сек', icon: Icons.forward_10, action: onSeekForward),
                    control(label: '${speed.toStringAsFixed(2)}×', icon: Icons.speed, action: onSpeed),
                    control(label: 'Субтитры', icon: Icons.subtitles_outlined, action: onSubtitles),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
