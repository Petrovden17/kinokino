import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../core/theme/app_theme.dart';

class PosterCard extends StatefulWidget {
  const PosterCard({super.key, required this.item, this.onTap});

  final MediaItem item;
  final VoidCallback? onTap;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final year = item.releaseDate.length >= 4
        ? item.releaseDate.substring(0, 4)
        : '';
    final kind = item.mediaType == 'tv' ? 'СЕРИАЛ' : 'ФИЛЬМ';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: (_hovered || _focused) ? 1.045 : 1.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _focused ? Theme.of(context).colorScheme.primary : Colors.transparent,
              width: _focused ? 3 : 0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: (_hovered || _focused) ? .38 : .12,
                ),
                blurRadius: (_hovered || _focused) ? 22 : 7,
                offset: Offset(0, (_hovered || _focused) ? 9 : 3),
              ),
            ],
          ),
          child: Material(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              canRequestFocus: true,
              onFocusChange: (focused) {
                if (mounted) setState(() => _focused = focused);
              },
              focusColor: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
              onTap: widget.onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        item.posterPath == null
                            ? const ColoredBox(
                                color: Color(0xFF202B3D),
                                child: Icon(
                                  Icons.movie_creation_outlined,
                                  size: 42,
                                  color: AppTheme.aqua,
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl:
                                    'https://image.tmdb.org/t/p/w342${item.posterPath}',
                                fit: BoxFit.cover,
                                placeholder: (_, __) => const ColoredBox(
                                  color: AppTheme.surfaceRaised,
                                ),
                                errorWidget: (_, __, ___) => const ColoredBox(
                                  color: Color(0xFF202B3D),
                                  child: Icon(
                                    Icons.movie_creation_outlined,
                                    size: 42,
                                    color: AppTheme.aqua,
                                  ),
                                ),
                              ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x44000000),
                                Colors.transparent,
                                Color(0xAA000000),
                              ],
                              stops: [0, .48, 1],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 9,
                          left: 9,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              kind,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .7,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                            fontSize: 13,
                          ),
                        ),
                        if (year.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            year,
                            style: const TextStyle(
                              color: AppTheme.aqua,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
