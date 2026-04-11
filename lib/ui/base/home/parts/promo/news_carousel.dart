import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../services/home/promo/rss.dart';
import '../../../../../services/platform/platform_provider.dart';

class NewsCarousel extends ConsumerWidget {
  const NewsCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final news = ref.watch(getNewsProvider);
    final platform = ref.watch(platformInfoProvider);

    return AnimatedSwitcher(
      duration: Durations.long1,
      child: news.when(
        data: (newsItems) {
          // Hide the carousel if there are no news items
          if (newsItems.isEmpty) {
            return const SizedBox.shrink(key: ValueKey('empty'));
          }

          return _buildCarousel(
            context,
            key: const ValueKey('news'),
            newsItems: newsItems,
            isDesktop: platform.isDesktop,
          );
        },
        loading: () => _buildCarousel(
          context,
          key: const ValueKey('loading'),
          newsItems: null,
          isDesktop: platform.isDesktop,
        ),
        error: (_, _) => const SizedBox.shrink(key: ValueKey('error')),
      ),
    );
  }

  Widget _buildCarousel(
    BuildContext context, {
    Key? key,
    required List<HomepageNewsItem>? newsItems,
    required bool isDesktop,
  }) {
    final List<Widget> children;
    if (newsItems == null) {
      children = List.generate(3, (_) => _LoadingCarouselItem());
    } else {
      children = newsItems
          .map((newsItem) => _NewsCarouselItem(newsItem: newsItem))
          .toList();
    }

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsGeometry.only(left: 8, top: 8),
          child: Text(
            'AKTUÁLIS',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 5),
          height: 120,
          child: CarouselView(
            itemExtent: 160,
            itemSnapping: isDesktop ? false : true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            shrinkExtent: 100,
            onTap: newsItems == null
                ? null
                : (index) async {
                    try {
                      await launchUrl(
                        newsItems[index].link,
                        mode: LaunchMode.inAppBrowserView,
                      );
                    } catch (_) {}
                  },
            children: children,
          ),
        ),
      ],
    );
  }
}

class _NewsCarouselItem extends StatelessWidget {
  final HomepageNewsItem newsItem;

  const _NewsCarouselItem({required this.newsItem});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Background image
        if (newsItem.backgroundImgUri != null)
          CachedNetworkImage(
            imageUrl: newsItem.backgroundImgUri!.toString(),
            fadeInDuration: Durations.medium3,
            fit: BoxFit.cover,
            height: 120,
            width: 160,
            errorWidget: (context, error, stackTrace) => Container(
              height: 100,
              width: 150,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceDim,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.image_not_supported, color: Colors.grey),
            ),
          )
        else
          Container(
            height: 120,
            width: 160,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceDim,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.article, color: Colors.grey),
          ),
        // Gradient overlay
        Container(
          height: 120,
          width: 160,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black87],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        // Title text
        Positioned(
          bottom: 8,
          left: 9,
          right: 6,
          child: Text(
            newsItem.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            softWrap: true,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _LoadingCarouselItem extends StatelessWidget {
  const _LoadingCarouselItem();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      width: 150,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceDim,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
