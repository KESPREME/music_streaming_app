// lib/widgets/home_collection_play_disc.dart
//
// The quick-play disc for a Home feed card (an album or playlist the feed sent).
// The disc itself is CollectionPlayDisc; this only knows how to fetch a feed item's
// songs.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../presentation/home/home_collections.dart';
import '../providers/music_provider.dart';
import '../services/home/home_models.dart';
import 'collection_play_disc.dart';

class HomeCollectionPlayDisc extends StatelessWidget {
  const HomeCollectionPlayDisc({super.key, required this.item, this.size = 34});

  final HomeItem item;
  final double size;

  static const double target = CollectionPlayDisc.target;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicProvider>();
    return CollectionPlayDisc(
      title: item.title,
      size: size,
      loadTracks: () => loadHomeCollectionTracks(provider, item),
    );
  }
}
