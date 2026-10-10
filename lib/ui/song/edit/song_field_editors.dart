import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:textfield_tags/textfield_tags.dart';

import '../../../data/song/song.dart';
import '../../../data/song/song_fields.dart';
import '../../../services/songs/filter.dart';
import '../../common/key_text.dart';

/// Which editor a metadata field gets, derived from its data shape and
/// whether it participates in filtering/search (which implies a value
/// vocabulary worth suggesting).
enum SongFieldEditorKind { text, suggestionText, chips, key }

SongFieldEditorKind songFieldEditorKind(SongField field) {
  if (field.hasUse(SongFieldUse.filterKey)) return SongFieldEditorKind.key;
  if (field.type == SongFieldType.list) return SongFieldEditorKind.chips;
  return field.hasFilterUse
      ? SongFieldEditorKind.suggestionText
      : SongFieldEditorKind.text;
}

/// The fields the song editor lets the user edit: everything the app shows
/// (non-core fields carrying a use) plus the core `key` field.
///
/// Known-but-unused vocabulary (no use) is skipped. Registry order is kept.
List<SongField> editableSongFields([Map<String, SongField>? registry]) {
  final effective = registry ?? defaultSongFieldRegistry;
  return [
    for (final field in effective.values)
      if (field.hasUse(SongFieldUse.filterKey) ||
          (!field.core && field.uses.isNotEmpty))
        field,
  ];
}

/// Renders the editor for a single `contentMap`-backed field. The `key` field
/// is not handled here (see [SongKeyField]).
class SongContentFieldEditor extends ConsumerWidget {
  const SongContentFieldEditor({
    required this.field,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final SongField field;

  /// The field's current raw `contentMap` value, or null when unset.
  final Object? value;

  /// Receives the new raw value; null means "clear the field".
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = songFieldEditorKind(field);
    final suggestsValues =
        kind == SongFieldEditorKind.suggestionText ||
        (kind == SongFieldEditorKind.chips && field.hasFilterUse);
    final suggestions = suggestsValues
        ? ref
                  .watch(selectableValuesForFilterableFieldProvider(field.apiName))
                  .value ??
              const <String>[]
        : const <String>[];

    return switch (kind) {
      SongFieldEditorKind.chips => _ChipsField(
        field: field,
        initialValues: _asStringList(value),
        suggestions: suggestions,
        onChanged: (tags) => onChanged(tags.isEmpty ? null : tags),
      ),
      SongFieldEditorKind.text || SongFieldEditorKind.suggestionText =>
        _TextField(
          field: field,
          initialValue: value is String ? value as String : null,
          suggestions: suggestions,
          onChanged: onChanged,
        ),
      SongFieldEditorKind.key => throw StateError(
        'key fields are rendered by SongKeyField',
      ),
    };
  }
}

List<String> _asStringList(Object? value) {
  if (value is List) return value.cast<String>();
  if (value is String && value.trim().isNotEmpty) return [value];
  return const [];
}

/// A labelled text field; when [suggestions] is non-empty it becomes a
/// typeahead field that still accepts custom values.
class _TextField extends StatefulWidget {
  const _TextField({
    required this.field,
    required this.initialValue,
    required this.suggestions,
    required this.onChanged,
  });

  final SongField field;
  final String? initialValue;
  final List<String> suggestions;
  final ValueChanged<Object?> onChanged;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  InputDecoration get _decoration => InputDecoration(
    labelText: widget.field.title,
    prefixIcon: widget.field.icon == null ? null : Icon(widget.field.icon),
    isDense: true,
  );

  @override
  Widget build(BuildContext context) {
    if (widget.suggestions.isEmpty) {
      return TextField(
        controller: _controller,
        decoration: _decoration,
        onChanged: widget.onChanged,
      );
    }

    return TypeAheadField<String>(
      controller: _controller,
      hideOnEmpty: true,
      hideOnUnfocus: true,
      suggestionsCallback: (pattern) {
        final query = pattern.trim().toLowerCase();
        final current = _controller.text.trim().toLowerCase();
        return [
          for (final suggestion in widget.suggestions)
            if (suggestion.toLowerCase() != current &&
                (query.isEmpty || suggestion.toLowerCase().contains(query)))
              suggestion,
        ];
      },
      itemBuilder: (context, suggestion) =>
          ListTile(dense: true, title: Text(suggestion)),
      onSelected: (suggestion) {
        _controller.text = suggestion;
        widget.onChanged(suggestion);
      },
      builder: (context, controller, focusNode) => TextField(
        controller: controller,
        focusNode: focusNode,
        decoration: _decoration,
        onChanged: widget.onChanged,
      ),
    );
  }
}

/// A tag input: values become removable chips; typing a separator or picking a
/// suggestion adds one, and the cursor keeps writing in the field below.
class _ChipsField extends StatefulWidget {
  const _ChipsField({
    required this.field,
    required this.initialValues,
    required this.suggestions,
    required this.onChanged,
  });

  final SongField field;
  final List<String> initialValues;
  final List<String> suggestions;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_ChipsField> createState() => _ChipsFieldState();
}

class _ChipsFieldState extends State<_ChipsField> {
  final StringTagController<String> _tagsController = StringTagController();
  List<String> _latest = const [];

  @override
  void initState() {
    super.initState();
    _latest = List.of(widget.initialValues);
    _tagsController.addListener(_onTagsChanged);
  }

  void _onTagsChanged() {
    final tags = List<String>.from(_tagsController.getTags ?? const []);
    if (listEquals(tags, _latest)) return;
    _latest = tags;
    widget.onChanged(tags);
  }

  @override
  void dispose() {
    _tagsController.removeListener(_onTagsChanged);
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        final chosen = _tagsController.getTags ?? const <String>[];
        return [
          for (final suggestion in widget.suggestions)
            if (!chosen.contains(suggestion) &&
                (query.isEmpty || suggestion.toLowerCase().contains(query)))
              suggestion,
        ];
      },
      onSelected: _tagsController.onTagSubmitted,
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) =>
          TextFieldTags<String>(
            textfieldTagsController: _tagsController,
            initialTags: widget.initialValues,
            textEditingController: textController,
            focusNode: focusNode,
            textSeparators: const [','],
            inputFieldBuilder: (context, values) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (values.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in values.tags)
                          InputChip(
                            label: Text(tag),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onDeleted: () => values.onTagRemoved(tag),
                          ),
                      ],
                    ),
                  ),
                TextField(
                  controller: values.textEditingController,
                  focusNode: values.focusNode,
                  decoration: InputDecoration(
                    labelText: widget.field.title,
                    prefixIcon: widget.field.icon == null
                        ? null
                        : Icon(widget.field.icon),
                    isDense: true,
                    errorText: values.error,
                  ),
                  onChanged: values.onTagChanged,
                  onSubmitted: values.onTagSubmitted,
                ),
              ],
            ),
          ),
    );
  }
}

/// The core `key` field: a multi-value picker over the fixed pitch/mode
/// vocabulary.
class SongKeyField extends StatefulWidget {
  const SongKeyField({required this.initialKeys, required this.onChanged, super.key});

  final List<KeyField> initialKeys;
  final ValueChanged<List<KeyField>> onChanged;

  @override
  State<SongKeyField> createState() => _SongKeyFieldState();
}

class _SongKeyFieldState extends State<SongKeyField> {
  late List<KeyField> _keys = List.of(widget.initialKeys);
  late String _pitch = keyPitchValues.first;
  late String _mode = keyModeValues.first;

  void _add() {
    final key = KeyField(_pitch, _mode);
    if (_keys.contains(key)) return;
    setState(() => _keys = [..._keys, key]);
    widget.onChanged(_keys);
  }

  void _remove(KeyField key) {
    setState(() => _keys = _keys.where((k) => k != key).toList());
    widget.onChanged(_keys);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.piano, size: 18),
            const SizedBox(width: 8),
            Text('Hangnem', style: theme.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 8),
        if (_keys.isEmpty)
          Text('Nincs hangnem megadva.', style: theme.textTheme.bodySmall)
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final key in _keys)
                InputChip(
                  label: Text(displayKeyField(key)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onDeleted: () => _remove(key),
                ),
            ],
          ),
        const SizedBox(height: 8),
        DropdownButton<String>(
          value: _pitch,
          isExpanded: true,
          items: [
            for (final pitch in keyPitchValues)
              DropdownMenuItem(value: pitch, child: Text(displayKeyPitch(pitch))),
          ],
          onChanged: (value) => setState(() => _pitch = value ?? _pitch),
        ),
        DropdownButton<String>(
          value: _mode,
          isExpanded: true,
          items: [
            for (final mode in keyModeValues)
              DropdownMenuItem(value: mode, child: Text(displayKeyMode(mode))),
          ],
          onChanged: (value) => setState(() => _mode = value ?? _mode),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.tonalIcon(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('Hozzáadás'),
          ),
        ),
      ],
    );
  }
}
