import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/database.dart';
import '../../data/song/song.dart';
import '../../ui/base/songs/widgets/filter/types/bank/state.dart';
import '../../ui/base/songs/widgets/filter/types/key/state.dart';

part 'filter.g.dart';

typedef KeyFilterSelectable = ({
  String label,
  Function(bool) onSelected,
  bool selected,
  bool addingKey,
});

String _placeholders(int count) => List.filled(count, '?').join(', ');

({String sql, List<Variable> variables}) _bankScopeClause(
  Set<String> bankFilters,
) {
  if (bankFilters.isEmpty) {
    return (sql: '1 = 1', variables: const []);
  }

  return (
    sql: 'songs.source_bank IN (${_placeholders(bankFilters.length)})',
    variables: bankFilters.map((bank) => Variable<String>(bank)).toList(),
  );
}

String _keyOptionSql({String select = 'value', String extraWhere = '1 = 1'}) =>
    '''
  WITH RECURSIVE split_values(value, rest) AS (
    SELECT '', TRIM(COALESCE(json_extract(songs.content_map, '\$.key'), '')) || ','
    FROM songs
    WHERE \$bank_scope
    UNION ALL
    SELECT
      TRIM(SUBSTR(rest, 1, INSTR(rest, ',') - 1)),
      LTRIM(SUBSTR(rest, INSTR(rest, ',') + 1))
    FROM split_values
    WHERE rest <> ''
  )
  SELECT DISTINCT $select
  FROM split_values
  WHERE value <> ''
    AND INSTR(value, '-') > 0
    AND $extraWhere
  ORDER BY $select COLLATE NOCASE
''';

@Riverpod(keepAlive: true)
Stream<List<KeyFilterSelectable>> selectablePitches(Ref ref) {
  final state = ref.watch(keyFilterStateProvider);
  final bankFilters = ref.watch(banksFilterStateProvider);
  final bankScope = _bankScopeClause(bankFilters);

  final addingFullKeys = state.modes.length == 1 && state.pitches.isEmpty;
  final sql = _keyOptionSql(
    select: addingFullKeys
        ? 'value'
        : "SUBSTR(value, 1, INSTR(value, '-') - 1)",
    extraWhere: addingFullKeys
        ? "SUBSTR(value, INSTR(value, '-') + 1) = ?"
        : '1 = 1',
  ).replaceFirst(r'$bank_scope', bankScope.sql);

  final variables = <Variable>[
    ...bankScope.variables,
    if (addingFullKeys) Variable<String>(state.modes.first),
  ];

  return db
      .customSelect(sql, variables: variables, readsFrom: {db.songs})
      .watch()
      .map((rows) {
        return rows
            .map((row) => row.data.values.single as String)
            .where((value) {
              if (!addingFullKeys) return true;
              return !state.keys.contains(KeyField.fromString(value)!);
            })
            .map(
              (value) => addingFullKeys
                  ? (
                      label: value,
                      onSelected: (selected) => ref
                          .read(keyFilterStateProvider.notifier)
                          .setKeyTo(KeyField.fromString(value)!, selected),
                      selected: false,
                      addingKey: true,
                    )
                  : (
                      label: value,
                      onSelected: (selected) => ref
                          .read(keyFilterStateProvider.notifier)
                          .setPitchTo(value, selected),
                      selected: state.pitches.contains(value),
                      addingKey: false,
                    ),
            )
            .toList(growable: false);
      });
}

@Riverpod(keepAlive: true)
Stream<List<KeyFilterSelectable>> selectableModes(Ref ref) {
  final state = ref.watch(keyFilterStateProvider);
  final bankFilters = ref.watch(banksFilterStateProvider);
  final bankScope = _bankScopeClause(bankFilters);

  final addingFullKeys = state.pitches.length == 1 && state.modes.isEmpty;
  final sql = _keyOptionSql(
    select: addingFullKeys ? 'value' : "SUBSTR(value, INSTR(value, '-') + 1)",
    extraWhere: addingFullKeys
        ? "SUBSTR(value, 1, INSTR(value, '-') - 1) = ?"
        : '1 = 1',
  ).replaceFirst(r'$bank_scope', bankScope.sql);

  final variables = <Variable>[
    ...bankScope.variables,
    if (addingFullKeys) Variable<String>(state.pitches.first),
  ];

  return db
      .customSelect(sql, variables: variables, readsFrom: {db.songs})
      .watch()
      .map((rows) {
        return rows
            .map((row) => row.data.values.single as String)
            .where((value) {
              if (!addingFullKeys) return true;
              return !state.keys.contains(KeyField.fromString(value)!);
            })
            .map(
              (value) => addingFullKeys
                  ? (
                      label: value,
                      onSelected: (selected) => ref
                          .read(keyFilterStateProvider.notifier)
                          .setKeyTo(KeyField.fromString(value)!, selected),
                      selected: false,
                      addingKey: true,
                    )
                  : (
                      label: value,
                      onSelected: (selected) => ref
                          .read(keyFilterStateProvider.notifier)
                          .setModeTo(value, selected),
                      selected: state.modes.contains(value),
                      addingKey: false,
                    ),
            )
            .toList(growable: false);
      });
}
