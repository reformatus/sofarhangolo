import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/bank/bank.dart';
import 'package:sofarhangolo/data/cue/slide.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/ui/song/state.dart';

Song _song({required String? sourceBank, String title = 'Cím'}) => Song(
  uuid: 'song-1',
  title: title,
  keyField: const [],
  contentMap: const {},
  sourceBank: sourceBank,
);

SongSlide _slide(Song song) =>
    SongSlide.from(song, viewType: SongViewType.lyrics);

void main() {
  group('SongSlide.contentChangedByOthers', () {
    test('is false when the content is unchanged', () {
      final song = _song(sourceBank: 'bank-1');
      final slide = _slide(song);

      expect(slide.contentChangedByOthers(song), isFalse);
    });

    test('is true for a bank song whose content changed', () {
      final song = _song(sourceBank: 'bank-1');
      final slide = _slide(song);
      final changed = song.copyWith(title: 'Új cím');

      expect(slide.contentChangedByOthers(changed), isTrue);
    });

    test('is false for a local song the user edited themselves', () {
      final song = _song(sourceBank: localBankUuid);
      final slide = _slide(song);
      final changed = song.copyWith(title: 'Új cím');

      expect(slide.contentChangedByOthers(changed), isFalse);
    });

    test('is false when the song is missing or has no shared hash', () {
      final song = _song(sourceBank: 'bank-1');
      final slide = _slide(song);

      expect(slide.contentChangedByOthers(null), isFalse);
    });
  });
}
