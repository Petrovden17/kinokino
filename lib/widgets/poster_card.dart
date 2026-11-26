import 'package:flutter/material.dart';
import '../models/media_item.dart';
import '../services/tmdb_service.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({
    required this.item,
    required this.service,
    this.onTap,
    super.key,
  });

  final MediaItem item;
  final TmdbService service;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final image = service.imageUrl(item.posterPath, size: 'w342');
    return SizedBox(
      width: 142,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: image.isEmpty
                    ? _placeholder()
                    : Image.network(
                        image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: const Color(0xFF182235),
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(strokeWidth: 2),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 3),
            Text(
              '${item.year}  •  ★ ${item.voteAverage.toStringAsFixed(1)}',
              style: TextStyle(color: Colors.white.withValues(alpha: .58), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: const Color(0xFF182235),
        alignment: Alignment.center,
        child: const Icon(Icons.movie_outlined, size: 36, color: Colors.white38),
      );
}
