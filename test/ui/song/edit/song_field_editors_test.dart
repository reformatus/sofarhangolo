import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/data/song/song_fields.dart';
import 'package:sofarhangolo/services/songs/filter.dart';
import 'package:sofarhangolo/ui/song/edit/song_field_editors.dart';

SongField _field(String apiName) => defaultSongFieldRegistry[apiName]!;

void main() {
  group('editableSongFields', () {
    test('includes everything shown plus the key field', () {
      final names = editableSongFields().map((f) => f.apiName).toList();

      expect(
        names,
        containsAll(<String>[
          'key',
          'composer',
          'lyricist',
          'translator',
          'title_original',
          'bible_ref',
          'songbook',
          'language',
          'genre',
          'content_tags',
          'holiday',
          'book',
          'instruments',
          'time_signature',
          'liturgical_role',
          'other_features',
          'dynamics',
        ]),
      );
    });

    test('excludes hidden vocabulary and other core fields', () {
      final names = editableSongFields().map((f) => f.apiName).toList();

      expect(names, isNot(contains('bpm')));
      expect(names, isNot(contains('year')));
      expect(names, isNot(contains('presentation')));
      expect(names, isNot(contains('title')));
      expect(names, isNot(contains('lyrics')));
      expect(names, isNot(contains('uuid')));
      expect(names, isNot(contains('pdf')));
      expect(names, isNot(contains('svg')));
    });
  });

  group('songFieldEditorKind', () {
    test('maps data shape + filter use to an editor', () {
      expect(songFieldEditorKind(_field('translator')), SongFieldEditorKind.text);
      expect(songFieldEditorKind(_field('composer')), SongFieldEditorKind.text);
      expect(
        songFieldEditorKind(_field('language')),
        SongFieldEditorKind.suggestionText,
      );
      expect(
        songFieldEditorKind(_field('dynamics')),
        SongFieldEditorKind.suggestionText,
      );
      expect(songFieldEditorKind(_field('genre')), SongFieldEditorKind.chips);
      expect(
        songFieldEditorKind(_field('content_tags')),
        SongFieldEditorKind.chips,
      );
      expect(songFieldEditorKind(_field('key')), SongFieldEditorKind.key);
    });
  });

  testWidgets('chips field adds a tag on a separator and reports the list', (
    tester,
  ) async {
    final field = _field('content_tags');
    final changes = <Object?>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectableValuesForFilterableFieldProvider(
            field.apiName,
          ).overrideWith((ref) async => const ['dicsőítés', 'karácsony']),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SongContentFieldEditor(
              field: field,
              value: null,
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'dicsőítés,');
    await tester.pumpAndSettle();

    expect(changes.last, const ['dicsőítés']);
    expect(find.widgetWithText(InputChip, 'dicsőítés'), findsOneWidget);
  });

  testWidgets('chips field reports null when the last tag is removed', (
    tester,
  ) async {
    final field = _field('content_tags');
    final changes = <Object?>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectableValuesForFilterableFieldProvider(
            field.apiName,
          ).overrideWith((ref) async => const <String>[]),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SongContentFieldEditor(
              field: field,
              value: const ['dicsőítés'],
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(InputChip),
        matching: find.byType(Icon),
      ),
    );
    await tester.pumpAndSettle();

    expect(changes.last, isNull);
  });

  testWidgets('suggestion field commits the highlighted option on Enter', (
    tester,
  ) async {
    final field = _field('language');
    final changes = <Object?>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectableValuesForFilterableFieldProvider(
            field.apiName,
          ).overrideWith((ref) async => const ['magyar', 'angol']),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SongContentFieldEditor(
              field: field,
              value: null,
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'mag');
    await tester.pumpAndSettle();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changes.last, 'magyar');
  });

  testWidgets('chips field commits the highlighted suggestion on Enter', (
    tester,
  ) async {
    final field = _field('content_tags');
    final changes = <Object?>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectableValuesForFilterableFieldProvider(
            field.apiName,
          ).overrideWith((ref) async => const ['dicsőítés', 'karácsony']),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SongContentFieldEditor(
              field: field,
              value: null,
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'dics');
    await tester.pumpAndSettle();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changes.last, const ['dicsőítés']);
    expect(find.widgetWithText(InputChip, 'dicsőítés'), findsOneWidget);
  });

  testWidgets('chips field commits free text on Enter when nothing matches', (
    tester,
  ) async {
    final field = _field('content_tags');
    final changes = <Object?>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectableValuesForFilterableFieldProvider(
            field.apiName,
          ).overrideWith((ref) async => const ['dicsőítés', 'karácsony']),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SongContentFieldEditor(
              field: field,
              value: null,
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ismeretlen');
    await tester.pumpAndSettle();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changes.last, const ['ismeretlen']);
  });

  testWidgets('chips field keeps the caret in the input after adding one', (
    tester,
  ) async {
    final field = _field('content_tags');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectableValuesForFilterableFieldProvider(
            field.apiName,
          ).overrideWith((ref) async => const <String>[]),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SongContentFieldEditor(
              field: field,
              value: null,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'dicsőítés,');
    await tester.pumpAndSettle();

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.focusNode?.hasFocus, isTrue);
  });

  testWidgets('key field adds the chosen key to the song', (tester) async {
    final changes = <List<KeyField>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongKeyField(initialKeys: const [], onChanged: changes.add),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hozzáadás'));
    await tester.pumpAndSettle();

    expect(changes.single, [KeyField('C', 'dur')]);
    expect(find.widgetWithText(InputChip, 'C-dúr'), findsOneWidget);
  });
}
