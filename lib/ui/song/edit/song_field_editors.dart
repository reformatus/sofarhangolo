import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      SongFieldEditorKind.text => _PlainTextField(
        field: field,
        initialValue: value is String ? value as String : null,
        onChanged: onChanged,
      ),
      SongFieldEditorKind.suggestionText => _SuggestionField(
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

InputDecoration _fieldDecoration(SongField field) => InputDecoration(
  labelText: field.title,
  prefixIcon: field.icon == null ? null : Icon(field.icon),
  isDense: true,
);

/// A plain text field (no value vocabulary).
class _PlainTextField extends StatefulWidget {
  const _PlainTextField({
    required this.field,
    required this.initialValue,
    required this.onChanged,
  });

  final SongField field;
  final String? initialValue;
  final ValueChanged<Object?> onChanged;

  @override
  State<_PlainTextField> createState() => _PlainTextFieldState();
}

class _PlainTextFieldState extends State<_PlainTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: _fieldDecoration(widget.field),
      onChanged: widget.onChanged,
    );
  }
}

/// A single-value text field with a value vocabulary. Uses the same
/// [Autocomplete] as the chip editor, so the suggestion dropdown and its
/// keyboard behaviour (first result highlighted, arrows move, Enter selects)
/// are identical; custom values are still accepted.
class _SuggestionField extends StatelessWidget {
  const _SuggestionField({
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
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: initialValue ?? ''),
      optionsBuilder: (value) => _matchingSuggestions(value.text, suggestions),
      onSelected: onChanged,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) =>
          TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: _fieldDecoration(field),
            onChanged: onChanged,
            onSubmitted: (_) => onFieldSubmitted(),
          ),
    );
  }
}

Iterable<String> _matchingSuggestions(String text, List<String> suggestions) {
  final query = text.trim().toLowerCase();
  return [
    for (final suggestion in suggestions)
      if (query.isEmpty || suggestion.toLowerCase().contains(query)) suggestion,
  ];
}

/// A tag input: values are chips inside the field; typing a separator or
/// picking a suggested result adds one, and the cursor keeps writing after
/// them. Enter selects the highlighted suggestion, comma commits free text.
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
  FocusNode? _inputFocusNode;

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
    // Keep the caret in the input so the next value can be typed right away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocusNode?.requestFocus();
    });
  }

  @override
  void dispose() {
    _tagsController.removeListener(_onTagsChanged);
    _tagsController.dispose();
    super.dispose();
  }

  /// Enter selects the highlighted suggestion; with no match it commits the
  /// typed text as a chip (comma also commits free text).
  void _submit(
    String text,
    InputFieldValues<String> values,
    VoidCallback onFieldSubmitted,
  ) {
    final query = text.trim().toLowerCase();
    final chosen = _tagsController.getTags ?? const <String>[];
    final hasMatch =
        query.isNotEmpty &&
        widget.suggestions.any(
          (s) => !chosen.contains(s) && s.toLowerCase().contains(query),
        );
    if (hasMatch) {
      onFieldSubmitted();
    } else {
      values.onTagSubmitted(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (value) {
        final chosen = _tagsController.getTags ?? const <String>[];
        return [
          for (final suggestion in _matchingSuggestions(
            value.text,
            widget.suggestions,
          ))
            if (!chosen.contains(suggestion)) suggestion,
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
            inputFieldBuilder: (context, values) {
              _inputFocusNode = values.focusNode;
              return LayoutBuilder(
                builder: (context, constraints) => InputDecorator(
                  decoration: InputDecoration(
                    label: _fieldLabel(widget.field),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: values.error,
                  ),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final tag in values.tags)
                        InputChip(
                          label: Text(tag),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onDeleted: () => values.onTagRemoved(tag),
                        ),
                      ConstrainedBox(
                        // Empty: fill the box like a normal field. With chips:
                        // sit inline after them, wrapping onto the next line.
                        constraints: BoxConstraints(
                          minWidth: 80,
                          maxWidth: values.tags.isEmpty
                              ? constraints.maxWidth
                              : 160,
                        ),
                        child: TextField(
                          controller: values.textEditingController,
                          focusNode: values.focusNode,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: values.onTagChanged,
                          onSubmitted: (text) =>
                              _submit(text, values, onFieldSubmitted),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }
}

/// A field label carrying the field's icon, used as the floating label of the
/// chip input.
Widget _fieldLabel(SongField field) {
  final icon = field.icon;
  if (icon == null) return Text(field.title);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16),
      const SizedBox(width: 4),
      Text(field.title),
    ],
  );
}

/// The core `key` field: a multi-value picker over the fixed pitch/mode
/// vocabulary.
class SongKeyField extends StatefulWidget {
  const SongKeyField({
    required this.initialKeys,
    required this.onChanged,
    super.key,
  });

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
