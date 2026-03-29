import 'dart:io';

Future<void> main() async {
  final root = Directory.current;
  final webDir = Directory('${root.path}/web');
  final buildWebDir = Directory('${root.path}/build/web');

  if (!await buildWebDir.exists()) {
    stderr.writeln('Missing build/web output. Run `flutter build web` first.');
    exitCode = 1;
    return;
  }

  final requiredFiles = [
    ('drift_worker.js', true),
    ('sqlite3.wasm', true),
    ('drift_worker.js.map', false),
    ('drift_worker.js.deps', false),
  ];

  for (final (fileName, required) in requiredFiles) {
    final source = File('${webDir.path}/$fileName');
    if (!await source.exists()) {
      if (required) {
        stderr.writeln(
          'Missing ${source.path}. Run `dart run tool/prepare_web.dart` first.',
        );
        exitCode = 1;
        return;
      }
      continue;
    }

    final target = File('${buildWebDir.path}/$fileName');
    await source.copy(target.path);
  }

  stdout.writeln('Copied Drift web runtime assets into ${buildWebDir.path}.');
}
