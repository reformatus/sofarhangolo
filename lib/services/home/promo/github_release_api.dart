import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/config.dart';
import '../../../data/log/logger.dart';
import 'github_release_api_stub.dart'
    if (dart.library.js_interop) 'github_release_api_web.dart'
    as github_api;

enum GithubReleaseTrack { stable, prerelease }

enum GithubReleaseAssetKind {
  windowsInstaller,
  windowsStore,
  macosDmg,
  linuxFlatpak,
  androidApk,
  iosIpa,
}

class GithubReleaseAsset {
  const GithubReleaseAsset({
    required this.kind,
    required this.name,
    required this.downloadUrl,
    required this.downloadCount,
    required this.sizeBytes,
  });

  final GithubReleaseAssetKind kind;
  final String name;
  final Uri downloadUrl;
  final int downloadCount;
  final int sizeBytes;

  String get title => switch (kind) {
    GithubReleaseAssetKind.windowsInstaller => 'Windows telepito',
    GithubReleaseAssetKind.windowsStore => 'Windows Store csomag',
    GithubReleaseAssetKind.macosDmg => 'macOS DMG',
    GithubReleaseAssetKind.linuxFlatpak => 'Linux Flatpak',
    GithubReleaseAssetKind.androidApk => 'Android APK',
    GithubReleaseAssetKind.iosIpa => 'iOS IPA',
  };
}

class GithubReleaseInfo {
  const GithubReleaseInfo({
    required this.track,
    required this.tagName,
    required this.htmlUrl,
    required this.assets,
  });

  final GithubReleaseTrack track;
  final String tagName;
  final Uri htmlUrl;
  final List<GithubReleaseAsset> assets;
}

class GithubReleaseTracks {
  const GithubReleaseTracks({required this.stable, required this.prerelease});

  final GithubReleaseInfo stable;
  final GithubReleaseInfo? prerelease;
}

final githubReleaseTracksProvider = FutureProvider<GithubReleaseTracks?>((
  ref,
) async {
  try {
    final response = await github_api.fetchGithubReleasesJson(
      '${appConfig.webappRoot}/downloads/releases.json',
    );
    final payload = jsonDecode(response);
    if (payload is! Map) {
      throw const FormatException('Release summary payload is not an object.');
    }

    final json = Map<String, dynamic>.from(payload);
    final stable = _parseReleaseSummary(
      json['stable'],
      fallbackTrack: GithubReleaseTrack.stable,
    );
    final prerelease = _parseReleaseSummary(
      json['prerelease'],
      fallbackTrack: GithubReleaseTrack.prerelease,
    );

    if (stable == null) {
      return null;
    }

    return GithubReleaseTracks(stable: stable, prerelease: prerelease);
  } catch (e, s) {
    log.warning(
      'Could not fetch GitHub releases for app download section.',
      e,
      s,
    );
    return null;
  }
});

GithubReleaseInfo? _parseReleaseSummary(
  Object? release, {
  required GithubReleaseTrack fallbackTrack,
}) {
  if (release is! Map) {
    return null;
  }

  final json = Map<String, dynamic>.from(release);
  final tagName = json['tagName'];
  final htmlUrl = json['htmlUrl'];
  final assetsJson = json['assets'];
  if (tagName is! String || htmlUrl is! String || assetsJson is! List) {
    return null;
  }

  final assets = assetsJson
      .whereType<Map>()
      .map((asset) => _parseAsset(Map<String, dynamic>.from(asset)))
      .whereType<GithubReleaseAsset>()
      .toList();

  return GithubReleaseInfo(
    track: switch (json['track']) {
      'stable' => GithubReleaseTrack.stable,
      'prerelease' => GithubReleaseTrack.prerelease,
      _ => fallbackTrack,
    },
    tagName: tagName,
    htmlUrl: Uri.parse(htmlUrl),
    assets: assets,
  );
}

GithubReleaseAsset? _parseAsset(Map<String, dynamic> asset) {
  final name = asset['name'];
  final downloadUrl = asset['browser_download_url'];
  final downloadCount = asset['download_count'];
  final sizeBytes = asset['size'];

  if (name is! String ||
      downloadUrl is! String ||
      downloadCount is! int ||
      sizeBytes is! int) {
    return null;
  }

  final lowerName = name.toLowerCase();
  final kind = switch (true) {
    _ when lowerName.endsWith('.exe') =>
      GithubReleaseAssetKind.windowsInstaller,
    _ when lowerName.endsWith('.msix') => GithubReleaseAssetKind.windowsStore,
    _ when lowerName.endsWith('.dmg') => GithubReleaseAssetKind.macosDmg,
    _ when lowerName.endsWith('.flatpak') =>
      GithubReleaseAssetKind.linuxFlatpak,
    _ when lowerName.endsWith('.apk') => GithubReleaseAssetKind.androidApk,
    _ when lowerName.endsWith('.ipa') => GithubReleaseAssetKind.iosIpa,
    _ => null,
  };

  if (kind == null) {
    return null;
  }

  return GithubReleaseAsset(
    kind: kind,
    name: name,
    downloadUrl: Uri.parse(downloadUrl),
    downloadCount: downloadCount,
    sizeBytes: sizeBytes,
  );
}
