import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/services/assets/get_song_asset.dart';
import 'package:sofarhangolo/ui/common/asset_bytes.dart';

Song _song() => Song(
  uuid: 'song-1',
  title: 'Dal',
  keyField: const [],
  contentMap: const {'pdf': 'song.pdf'},
);

/// Calls [fetchAssetBytes] once from [State.initState] and reports the outcome.
class _Fetcher extends ConsumerStatefulWidget {
  const _Fetcher({required this.song, required this.onDone});

  final Song song;
  final void Function(Uint8List? bytes, Object? error) onDone;

  @override
  ConsumerState<_Fetcher> createState() => _FetcherState();
}

class _FetcherState extends ConsumerState<_Fetcher> {
  @override
  void initState() {
    super.initState();
    fetchAssetBytes(ref, widget.song, 'pdf').then(
      (bytes) => widget.onDone(bytes, null),
      onError: (Object error) => widget.onDone(null, error),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Widget _app({
  required Song song,
  required Stream<AssetResult> Function(Ref ref) asset,
  required void Function(Uint8List? bytes, Object? error) onDone,
}) {
  return ProviderScope(
    overrides: [getSongAssetProvider(song, 'pdf').overrideWith(asset)],
    child: MaterialApp(home: _Fetcher(song: song, onDone: onDone)),
  );
}

void main() {
  testWidgets('waits past the progress event for the bytes', (tester) async {
    final song = _song();
    final bytes = Uint8List.fromList([1, 2, 3]);
    Uint8List? result;
    Object? resultError;
    var completed = false;

    await tester.pumpWidget(
      _app(
        song: song,
        asset: (ref) => Stream.fromIterable([
          (progress: null, data: null),
          (progress: 1.0, data: bytes),
        ]),
        onDone: (value, error) {
          result = value;
          resultError = error;
          completed = true;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(resultError, isNull);
    expect(result, same(bytes));
  });

  testWidgets('surfaces a download failure instead of hanging', (tester) async {
    final song = _song();
    Object? resultError;
    var completed = false;

    await tester.pumpWidget(
      _app(
        song: song,
        asset: (ref) => Stream<AssetResult>.error(StateError('offline')),
        onDone: (value, error) {
          resultError = error;
          completed = true;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(resultError, isA<StateError>());
  });
}
