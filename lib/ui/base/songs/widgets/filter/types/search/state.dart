import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../../../../services/songs/field_registry.dart';
import '../field_type.dart';

part 'state.g.dart';

@Riverpod(keepAlive: true)
class SearchFieldsState extends _$SearchFieldsState {
  @override
  List<String> build() {
    return [];
  }

  void addSearchField(String field) {
    if (!state.contains(field)) {
      state.add(field);
      ref.notifyListeners();
    }
  }

  void removeSearchField(String field) {
    if (state.length < 2) {
      return; // Make sure at least one column stays selected
    }
    state.remove(field);
    ref.notifyListeners();
  }
}

@Riverpod(keepAlive: true)
Future<List<SongFieldDefinition>> availableSearchFields(Ref ref) async {
  final catalog = await ref.watch(activeSongFieldCatalogProvider.future);
  final fields = catalog.searchableFields.toList(growable: false);
  fields.sort((a, b) => a.titleHu.compareTo(b.titleHu));
  return fields;
}

@Riverpod(keepAlive: true)
Future<List<String>> effectiveSearchFields(Ref ref) async {
  final availableFields = await ref.watch(availableSearchFieldsProvider.future);
  final selectedFields = ref.watch(searchFieldsStateProvider);
  final availableFieldNames = availableFields
      .map((field) => field.field)
      .toSet();

  final effectiveSelection = selectedFields
      .where(availableFieldNames.contains)
      .toList(growable: false);
  if (effectiveSelection.isNotEmpty) {
    return effectiveSelection;
  }

  return availableFields.map((field) => field.field).toList(growable: false);
}

@Riverpod(keepAlive: true)
class SearchStringState extends _$SearchStringState {
  @override
  String build() {
    return "";
  }

  void set(String value) {
    state = value;
  }

  void clear() {
    state = "";
  }
}
