// far future todo: make this plugin extendable / bank provider extendable

// let plugins provide filter ui and logic
import 'package:flutter/material.dart';

// TODO read this from bank schema
const Map<String, Map<String, dynamic>> songFieldsMap = {
  'title': {'title_hu': 'Cím', 'type': 'searchable', 'icon': Icons.text_fields},
  'title_original': {
    'title_hu': 'Cím (eredeti)',
    'type': 'searchable',
    'icon': Icons.wrap_text,
  },
  'first_line': {
    'title_hu': 'Kezdősor',
    'type': 'searchable',
    'icon': Icons.short_text,
  },
  'lyrics': {
    'title_hu': 'Dalszöveg',
    'type': 'searchable',
    'icon': Icons.text_snippet,
  },
  'composer': {
    'title_hu': 'Dalszerző',
    'type': 'searchable',
    'icon': Icons.music_note,
  },
  'lyricist': {
    'title_hu': 'Szövegíró',
    'type': 'searchable',
    'icon': Icons.edit,
  },
  'translator': {
    'title_hu': 'Fordította',
    'type': 'searchable',
    'icon': Icons.translate,
  },
  'bible_ref': {
    'title_hu': 'Igeszakasz',
    'type': 'searchable',
    'icon': Icons.book,
  },
  'ref_songbook': {
    'title_hu': 'Református Énekeskönyv',
    'type': 'searchable',
    'icon': Icons.menu_book,
  },
  'language': {
    'title_hu': 'Eredeti nyelv',
    'type': 'filterable_multiselect_tags',
    'icon': Icons.language,
  },
  'tempo': {
    'title_hu': 'Tempó',
    'type': 'filterable_multiselect',
    'icon': Icons.speed,
  },
  'ambitus': {
    'title_hu': 'Hangterjedelem',
    'type': 'filterable_multiselect',
    'icon': Icons.height,
  },
  'key': {'title_hu': 'Hangnem', 'type': 'filterable_key', 'icon': Icons.piano},
  'genre': {
    'title_hu': 'Stílus / műfaj',
    'type': 'filterable_multiselect_tags',
    'icon': Icons.style,
  },
  'content_tags': {
    'title_hu': 'Tartalomcímkék',
    'type': 'filterable_multiselect_tags',
    'icon': Icons.label_sharp,
  },
  'holiday': {
    'title_hu': 'Ünnep',
    'type': 'filterable_multiselect_tags',
    'icon': Icons.celebration,
  },
  'sofar': {
    'title_hu': 'Sófár kottafüzet',
    'type': 'filterable_multiselect_tags',
    'icon': Icons.calendar_month,
  },
  // TODO implement
  /*'dynamics': {
    'title_hu': 'Dinamika',
    'type': 'dynamics',
    'icon': Icons.volume_down,
  }*/
};

enum FieldType {
  multiselect("filterable_multiselect", isFilterable: true),
  multiselectTags(
    "filterable_multiselect_tags",
    isFilterable: true,
    commaDividedValues: true,
  ),
  key("filterable_key", isFilterable: true),
  searchable("searchable", isSearchable: true);

  const FieldType(
    this.name, {
    this.isSearchable = false,
    this.isFilterable = false,
    this.commaDividedValues = false,
  });
  final String name;
  final bool isSearchable;
  final bool isFilterable;
  final bool commaDividedValues;

  // Static map for fast lookup
  static final Map<String, FieldType> _typeMap = {
    for (var field in FieldType.values) field.name: field,
  };

  static FieldType? fromString(String value) => _typeMap[value];
}
