import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.item, this.onTap});
  final MediaItem item;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 145,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: item.posterPath == null
              ? const ColoredBox(color: Color(0xFF202B3D), child: Icon(Icons.movie))
              : CachedNetworkImage(
                  imageUrl: 'https://image.tmdb.org/t/p/w342${item.posterPath}',
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF202B3D), child: Icon(Icons.movie)),
                ),
          ),
        ),
        const SizedBox(height: 7),
        Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}
