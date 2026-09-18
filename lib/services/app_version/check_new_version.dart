import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../config/config.dart';
import '../../data/log/logger.dart';
import '../http/dio_provider.dart';
import '../preferences/providers/general.dart';

part 'check_new_version.g.dart';

typedef VersionInfo = ({
  String versionNumber,
  String releaseNotesMd,
  Uri releaseInfoLink,
});

@Riverpod(keepAlive: true)
Future<VersionInfo?> checkNewVersion(Ref ref) async {
  try {
    final dio = ref.read(dioProvider);
    final testingMode = ref.watch(generalPreferencesProvider).testingMode;
    final latestRelease = await _getLatestRelease(
      dio: dio,
      testingMode: testingMode,
    );
    if (latestRelease == null) return null;

    final latestVersion = (latestRelease['tag_name'] as String);

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    final latest = _SemanticVersion.tryParse(latestVersion);
    final current = _SemanticVersion.tryParse(currentVersion);

    if (latest == null || current == null) {
      log.warning('Could not parse versions while checking for updates.', {
        'latest': latestVersion,
        'current': currentVersion,
      });
      return null;
    }

    if (latest.compareTo(current) <= 0) return null;

    log.warning('Új verzió elérhető!');

    return (
      versionNumber: latestVersion,
      releaseNotesMd: latestRelease['body'] as String? ?? '',
      releaseInfoLink: Uri.parse(latestRelease['html_url'] as String),
    );
  } catch (e, s) {
    log.warning("Couldn't check for new versions:", e, s);
    return null;
  }
}

Future<Map<String, dynamic>?> _getLatestRelease({
  required Dio dio,
  required bool testingMode,
}) async {
  if (!testingMode) {
    return (await dio.get<Map<String, dynamic>>(
      '${appConfig.gitHubApiRoot}/releases/latest',
    )).data;
  }

  final releases = (await dio.get<List<dynamic>>(
    '${appConfig.gitHubApiRoot}/releases?per_page=20',
  )).data;

  if (releases == null) return null;

  for (final release in releases) {
    if (release is! Map<String, dynamic>) continue;
    if (release['draft'] == true) continue;
    if (release['prerelease'] == true) return release;
  }

  return null;
}

class _SemanticVersion implements Comparable<_SemanticVersion> {
  const _SemanticVersion(this.major, this.minor, this.patch, this.preRelease);

  final int major;
  final int minor;
  final int patch;
  final List<_SemanticIdentifier> preRelease;

  static _SemanticVersion? tryParse(String value) {
    var normalized = value.trim();
    if (normalized.startsWith('v')) {
      normalized = normalized.substring(1);
    }

    normalized = normalized.split('+').first;
    final separatorIndex = normalized.indexOf('-');
    final core =
        (separatorIndex == -1
                ? normalized
                : normalized.substring(0, separatorIndex))
            .split('.');
    if (core.length != 3) return null;

    final major = int.tryParse(core[0]);
    final minor = int.tryParse(core[1]);
    final patch = int.tryParse(core[2]);
    if (major == null || minor == null || patch == null) {
      return null;
    }

    final preRelease = separatorIndex == -1
        ? <_SemanticIdentifier>[]
        : normalized
              .substring(separatorIndex + 1)
              .split('.')
              .where((part) => part.isNotEmpty)
              .map((part) => _SemanticIdentifier.parse(part))
              .toList(growable: false);

    return _SemanticVersion(major, minor, patch, preRelease);
  }

  @override
  int compareTo(_SemanticVersion other) {
    final majorCompare = major.compareTo(other.major);
    if (majorCompare != 0) return majorCompare;

    final minorCompare = minor.compareTo(other.minor);
    if (minorCompare != 0) return minorCompare;

    final patchCompare = patch.compareTo(other.patch);
    if (patchCompare != 0) return patchCompare;

    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;

    final shortestLength = preRelease.length < other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;

    for (var index = 0; index < shortestLength; index++) {
      final compare = preRelease[index].compareTo(other.preRelease[index]);
      if (compare != 0) return compare;
    }

    return preRelease.length.compareTo(other.preRelease.length);
  }
}

class _SemanticIdentifier implements Comparable<_SemanticIdentifier> {
  const _SemanticIdentifier._({
    required this.value,
    required this.numericValue,
  });

  final String value;
  final int? numericValue;

  factory _SemanticIdentifier.parse(String value) {
    return _SemanticIdentifier._(
      value: value,
      numericValue: int.tryParse(value),
    );
  }

  @override
  int compareTo(_SemanticIdentifier other) {
    if (numericValue != null && other.numericValue != null) {
      return numericValue!.compareTo(other.numericValue!);
    }
    if (numericValue != null) return -1;
    if (other.numericValue != null) return 1;
    return value.compareTo(other.value);
  }
}
