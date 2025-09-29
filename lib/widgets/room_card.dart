// lib/widgets/room_card.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class RoomCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String colorHex; // ARGB: 'FFB8E1FF'
  final String route;
  final String? imageAsset; // e.g. 'assets/rooms/living_room.jpg'

  const RoomCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.colorHex,
    required this.route,
    this.imageAsset,
  });

  Color _parseHex(String hex) {
    try {
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return Colors.grey.shade300;
    }
  }

  Future<bool> _assetExists(String path) async {
    try {
      // AssetManifest.json list contains packaged assets. We check for presence.
      final manifest = await rootBundle.loadString('AssetManifest.json');
      return manifest.contains('"$path"');
    } catch (e) {
      // If anything fails, assume false
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallbackBg = _parseHex(colorHex);

    return GestureDetector(
      onTap: () => GoRouter.of(context).go(route),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.hardEdge,
        elevation: 2,
        child: Container(
          color: fallbackBg,
          child: Stack(
            children: [
              // If an image asset is provided, check its existence then show it
              if (imageAsset != null)
                FutureBuilder<bool>(
                  future: _assetExists(imageAsset!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      // still checking: show small shimmer-ish placeholder
                      return Positioned.fill(
                        child: Container(
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }

                    final exists = snapshot.data == true;
                    if (exists) {
                      // load the asset; errorBuilder handles decode issues
                      return Positioned.fill(
                        child: Image.asset(
                          imageAsset!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          // If decoding fails, show fallback container
                          errorBuilder: (ctx, err, stack) {
                            return Container(
                              color: fallbackBg,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.all(12),
                              child: const Icon(Icons.broken_image,
                                  size: 40, color: Colors.white70),
                            );
                          },
                        ),
                      );
                    } else {
                      // asset not found in manifest -> visible fallback
                      return Positioned.fill(
                        child: Container(
                          color: fallbackBg,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.image_not_supported,
                                  size: 36, color: Colors.white70),
                              const SizedBox(height: 6),
                              Text(
                                'Image not packaged',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.9)),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                imageAsset ?? '',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white70.withOpacity(0.85),
                                    fontSize: 10),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                ),
              // gradient overlay for readability
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.0),
                        Colors.black.withOpacity(0.35),
                      ],
                    ),
                  ),
                ),
              ),
              // content: top-left pill + bottom-left title
              Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        subtitle,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
