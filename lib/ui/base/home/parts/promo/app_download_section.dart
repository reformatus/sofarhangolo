import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../config/config.dart';
import '../../../../../services/home/promo/github_release_api.dart';
import '../../../../../services/home/promo/rss.dart';

class AppDownloadSection extends ConsumerStatefulWidget {
  const AppDownloadSection({super.key});

  @override
  ConsumerState<AppDownloadSection> createState() => _AppDownloadSectionState();
}

class _AppDownloadSectionState extends ConsumerState<AppDownloadSection> {
  GithubReleaseTrack _selectedTrack = GithubReleaseTrack.stable;

  @override
  Widget build(BuildContext context) {
    final releases = ref.watch(githubReleaseTracksProvider);
    final buttons = ref.watch(getButtonsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final storeLinks = _buildStoreLinks(
      buttons.maybeWhen(data: (value) => value, orElse: () => const []),
    );

    return Card.outlined(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'App letoltese',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Aruhazbol egyszerubb telepiteni. Kozvetlen csomag akkor jo, ha azt keresed.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (storeLinks.isNotEmpty) ...[
              const SizedBox(height: 16),
              _StoreLinkGrid(storeLinks: storeLinks),
            ],
            const SizedBox(height: 18),
            releases.when(
              loading: () => const _ReleaseLoadingState(),
              error: (_, _) => const _ReleaseErrorState(),
              data: (tracks) {
                if (tracks == null) {
                  return const _ReleaseErrorState();
                }

                final effectiveTrack =
                    _selectedTrack == GithubReleaseTrack.prerelease &&
                        tracks.prerelease == null
                    ? GithubReleaseTrack.stable
                    : _selectedTrack;

                final selectedRelease = switch (effectiveTrack) {
                  GithubReleaseTrack.stable => tracks.stable,
                  GithubReleaseTrack.prerelease => tracks.prerelease,
                };
                final selectedAssets = selectedRelease?.assets ?? const [];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TrackToggle(
                      stable: tracks.stable,
                      prerelease: tracks.prerelease,
                      selectedTrack: effectiveTrack,
                      onChanged: (track) {
                        setState(() {
                          _selectedTrack = track;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (selectedRelease != null)
                      Row(
                        children: [
                          Text(
                            'Aktualis csatorna: ${selectedRelease.tagName}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(width: 8),
                          ActionChip(
                            label: const Text('Kiadasi oldal'),
                            onPressed: () => _openUrl(selectedRelease.htmlUrl),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    if (selectedRelease == null)
                      const Text(
                        'Ehhez a csatornahoz most nincs nyilvanos kiadas.',
                      )
                    else if (selectedAssets.isEmpty)
                      const Text(
                        'Ehhez a kiadashoz most nincs letoltheto csomag.',
                      )
                    else
                      _AssetGrid(assets: selectedAssets),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<_StoreLink> _buildStoreLinks(List<HomepageButtonItem> buttonItems) {
    final links = <_StoreLink>[];

    if (appConfig.androidStoreUrl case final androidStoreUrl?) {
      links.add(
        _StoreLink(
          title: 'Google Play',
          subtitle: 'Android',
          url: Uri.parse(androidStoreUrl),
          icon: Icons.shop_outlined,
        ),
      );
    }

    if (appConfig.iosStoreUrl case final iosStoreUrl?) {
      links.add(
        _StoreLink(
          title: 'App Store',
          subtitle: 'iPhone es iPad',
          url: Uri.parse(iosStoreUrl),
          icon: Icons.phone_iphone_outlined,
        ),
      );
    }

    for (final item in buttonItems) {
      final host = item.link.host.toLowerCase();
      final title = item.title.toLowerCase();
      if (host.contains('apps.microsoft.com') || title.contains('microsoft')) {
        links.add(
          _StoreLink(
            title: item.title,
            subtitle: 'Windows',
            url: item.link,
            icon: Icons.window_outlined,
          ),
        );
      } else if (host.contains('apps.apple.com') &&
          !links.any((link) => link.url == item.link)) {
        links.add(
          _StoreLink(
            title: item.title,
            subtitle: 'Apple',
            url: item.link,
            icon: Icons.apple_outlined,
          ),
        );
      } else if (host.contains('play.google.com') &&
          !links.any((link) => link.url == item.link)) {
        links.add(
          _StoreLink(
            title: item.title,
            subtitle: 'Android',
            url: item.link,
            icon: Icons.shop_outlined,
          ),
        );
      }
    }

    return links;
  }

  Future<void> _openUrl(Uri url) async {
    await launchUrl(url, webOnlyWindowName: '_blank');
  }
}

class _StoreLink {
  const _StoreLink({
    required this.title,
    required this.subtitle,
    required this.url,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final Uri url;
  final IconData icon;
}

class _StoreLinkGrid extends StatelessWidget {
  const _StoreLinkGrid({required this.storeLinks});

  final List<_StoreLink> storeLinks;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: storeLinks
          .map(
            (storeLink) => SizedBox(
              width: 260,
              child: FilledButton.tonalIcon(
                onPressed: () =>
                    launchUrl(storeLink.url, webOnlyWindowName: '_blank'),
                icon: Icon(storeLink.icon),
                label: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(storeLink.title),
                    Text(
                      storeLink.subtitle,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                style: FilledButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _TrackToggle extends StatelessWidget {
  const _TrackToggle({
    required this.stable,
    required this.prerelease,
    required this.selectedTrack,
    required this.onChanged,
  });

  final GithubReleaseInfo stable;
  final GithubReleaseInfo? prerelease;
  final GithubReleaseTrack selectedTrack;
  final ValueChanged<GithubReleaseTrack> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _TrackCard(
          title: 'Stabil kiadas',
          description: 'Ajanlott a legtobb felhasznalonak.',
          version: stable.tagName,
          selected: selectedTrack == GithubReleaseTrack.stable,
          enabled: true,
          onTap: () => onChanged(GithubReleaseTrack.stable),
        ),
        _TrackCard(
          title: 'Elozetes kiadas',
          description: 'Uj funkciok hamarabb, kevesebb stabilitassal.',
          version: prerelease?.tagName ?? 'Nincs aktiv eloze teszt',
          selected: selectedTrack == GithubReleaseTrack.prerelease,
          enabled: prerelease != null,
          onTap: prerelease == null
              ? null
              : () => onChanged(GithubReleaseTrack.prerelease),
        ),
      ],
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.title,
    required this.description,
    required this.version,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String description;
  final String version;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 260,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            color: selected
                ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                : colorScheme.surface,
          ),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: enabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(description),
                const SizedBox(height: 8),
                Text(
                  version,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AssetGrid extends StatelessWidget {
  const _AssetGrid({required this.assets});

  final List<GithubReleaseAsset> assets;

  @override
  Widget build(BuildContext context) {
    final orderedAssets = [...assets]
      ..sort((left, right) => left.kind.index.compareTo(right.kind.index));

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: orderedAssets
          .map((asset) => _AssetCard(asset: asset))
          .toList(growable: false),
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({required this.asset});

  final GithubReleaseAsset asset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Card.filled(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(asset.title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                asset.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TagChip(text: '${asset.downloadCount} letoltes'),
                  _TagChip(text: _formatBytes(asset.sizeBytes)),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    launchUrl(asset.downloadUrl, webOnlyWindowName: '_blank'),
                child: const Text('Letoltes'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    double value = bytes.toDouble();
    int unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }

    final digits = value >= 100 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(text, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}

class _ReleaseLoadingState extends StatelessWidget {
  const _ReleaseLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: LinearProgressIndicator(minHeight: 3),
    );
  }
}

class _ReleaseErrorState extends StatelessWidget {
  const _ReleaseErrorState();

  @override
  Widget build(BuildContext context) {
    return Text(
      'A GitHub kiadasok most nem toltodtek be. Az aruhaz linkek ettol meg elerhetok.',
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}
