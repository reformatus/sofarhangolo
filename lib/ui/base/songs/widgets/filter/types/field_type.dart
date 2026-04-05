import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';

const String fallbackBankSongFieldsJson = '''
{
  "title": {
    "title_hu": "Cím",
    "type": "searchable",
    "icon": "text_fields"
  },
  "title_original": {
    "title_hu": "Cím (eredeti)",
    "type": "searchable",
    "icon": "wrap_text"
  },
  "first_line": {
    "title_hu": "Kezdősor",
    "type": "searchable",
    "icon": "short_text"
  },
  "lyrics": {
    "title_hu": "Dalszöveg",
    "type": "searchable",
    "icon": "text_snippet"
  },
  "composer": {
    "title_hu": "Dalszerző",
    "type": "searchable",
    "icon": "music_note"
  },
  "lyricist": {
    "title_hu": "Szövegíró",
    "type": "searchable",
    "icon": "edit"
  },
  "translator": {
    "title_hu": "Fordította",
    "type": "searchable",
    "icon": "translate"
  },
  "bible_ref": {
    "title_hu": "Igeszakasz",
    "type": "searchable",
    "icon": "book"
  },
  "ref_songbook": {
    "title_hu": "Református Énekeskönyv",
    "type": "searchable",
    "icon": "menu_book"
  },
  "language": {
    "title_hu": "Eredeti nyelv",
    "type": "filterable_multiselect_tags",
    "icon": "language"
  },
  "tempo": {
    "title_hu": "Tempó",
    "type": "filterable_multiselect",
    "icon": "speed"
  },
  "ambitus": {
    "title_hu": "Hangterjedelem",
    "type": "filterable_multiselect",
    "icon": "height"
  },
  "key": {
    "title_hu": "Hangnem",
    "type": "filterable_key",
    "icon": "piano"
  },
  "genre": {
    "title_hu": "Stílus / műfaj",
    "type": "filterable_multiselect_tags",
    "icon": "style"
  },
  "content_tags": {
    "title_hu": "Tartalomcímkék",
    "type": "filterable_multiselect_tags",
    "icon": "label_sharp"
  },
  "holiday": {
    "title_hu": "Ünnep",
    "type": "filterable_multiselect_tags",
    "icon": "celebration"
  },
  "sofar": {
    "title_hu": "Sófár kottafüzet",
    "type": "filterable_multiselect_tags",
    "icon": "calendar_month"
  }
}
''';

final SongFieldCatalog fallbackSongFieldCatalog = SongFieldCatalog.parse(
  fallbackBankSongFieldsJson,
);

final Map<String, IconData> _iconsByName = UnmodifiableMapView({
  'book': Icons.book,
  'calendar_month': Icons.calendar_month,
  'celebration': Icons.celebration,
  'edit': Icons.edit,
  'height': Icons.height,
  'label_sharp': Icons.label_sharp,
  'language': Icons.language,
  'menu_book': Icons.menu_book,
  'music_note': Icons.music_note,
  'piano': Icons.piano,
  'short_text': Icons.short_text,
  'speed': Icons.speed,
  'style': Icons.style,
  'text_fields': Icons.text_fields,
  'text_snippet': Icons.text_snippet,
  'translate': Icons.translate,
  'wrap_text': Icons.wrap_text,
});

enum FieldType {
  multiselect('filterable_multiselect', isFilterable: true),
  multiselectTags(
    'filterable_multiselect_tags',
    isFilterable: true,
    commaDividedValues: true,
  ),
  key('filterable_key', isFilterable: true, commaDividedValues: true),
  searchable('searchable', isSearchable: true);

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

  static final Map<String, FieldType> _typeMap = {
    for (final field in FieldType.values) field.name: field,
  };

  static FieldType? fromString(String value) => _typeMap[value];
}

class SongFieldDefinition {
  const SongFieldDefinition({
    required this.field,
    required this.titleHu,
    required this.type,
    required this.icon,
    required this.iconName,
  });

  final String field;
  final String titleHu;
  final FieldType type;
  final IconData icon;
  final String iconName;

  bool get isFilterable => type.isFilterable;
  bool get isSearchable => type.isSearchable;
  bool get commaDividedValues => type.commaDividedValues;

  factory SongFieldDefinition.fromJson(
    String field,
    Map<String, dynamic> json,
  ) {
    final type = FieldType.fromString((json['type'] ?? '').toString());
    if (type == null) {
      throw FormatException('Unknown field type for "$field": ${json['type']}');
    }

    final iconName = (json['icon'] ?? '').toString();
    final icon = _iconsByName[iconName];
    if (icon == null) {
      throw FormatException('Unknown icon for "$field": $iconName');
    }

    final titleHu = (json['title_hu'] ?? json['titleHu'] ?? '').toString();
    if (titleHu.trim().isEmpty) {
      throw FormatException('Missing Hungarian title for "$field"');
    }

    return SongFieldDefinition(
      field: field,
      titleHu: titleHu,
      type: type,
      icon: icon,
      iconName: iconName,
    );
  }

  Map<String, Object?> toJson() => {
    'title_hu': titleHu,
    'type': type.name,
    'icon': iconName,
  };
}

class SongFieldCatalog {
  SongFieldCatalog._(Map<String, SongFieldDefinition> fields)
    : fields = UnmodifiableMapView(fields);

  final Map<String, SongFieldDefinition> fields;

  Iterable<SongFieldDefinition> get searchableFields =>
      fields.values.where((field) => field.isSearchable);

  Iterable<SongFieldDefinition> get filterableFields =>
      fields.values.where((field) => field.isFilterable);

  SongFieldDefinition? operator [](String field) => fields[field];

  bool contains(String field) => fields.containsKey(field);

  static SongFieldCatalog parse(Object? source) {
    final parsed = _normalizeSource(source);
    if (parsed == null || parsed.isEmpty) {
      return fallbackSongFieldCatalog;
    }

    return SongFieldCatalog._({
      for (final entry in parsed.entries)
        if (entry.value is Map)
          entry.key: SongFieldDefinition.fromJson(
            entry.key,
            (entry.value as Map).cast<String, dynamic>(),
          ),
    });
  }

  static Map<String, dynamic>? _normalizeSource(Object? source) {
    if (source == null) return null;

    if (source is String) {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw FormatException('Song field catalog must be a JSON object');
    }

    if (source is Map<String, dynamic>) {
      return source;
    }

    if (source is Map) {
      return source.map((key, value) => MapEntry(key.toString(), value));
    }

    throw FormatException(
      'Unsupported song field catalog source: ${source.runtimeType}',
    );
  }
}

SongFieldCatalog mergeSongFieldCatalogs(Iterable<SongFieldCatalog> catalogs) {
  final merged = <String, SongFieldDefinition>{};
  for (final catalog in catalogs) {
    merged.addAll(catalog.fields);
  }

  if (merged.isEmpty) {
    return fallbackSongFieldCatalog;
  }

  return SongFieldCatalog._(merged);
}
