import 'package:flutter/material.dart';

/// How a field's values are shaped in the bank API and in contentMap.
enum SongFieldType { text, list }

/// Relative importance of a search-use field's matches when ranking
/// unified text search results: title > people > metadata > lyrics.
/// The [weight] is the bm25 multiplier the query builder passes for
/// columns in this group — only the ratios matter, and re-tuning them
/// is a one-edit change here.
enum SongSearchGroup {
  /// Short and dense: a title hit is the strongest relevance signal.
  title(10.0),

  /// Composer, lyricist, translator: finding a song by its people is a
  /// common intent that should outrank incidental text matches.
  people(5.0),

  /// Original titles, scripture references, songbook entries.
  metadata(2.0),

  /// Lyrics are long, so matches are plentiful but rarely the best
  /// answer — they rank last within a relevance tier.
  lyrics(1.0);

  const SongSearchGroup(this.weight);

  /// Relative bm25 multiplier for columns of this group. Ordering tiers
  /// (exact > LIKE > fts-only) dominate ranking; this only orders
  /// results within a tier.
  final double weight;
}

/// What the app does with a field. Storage itself is open-world: unknown
/// fields still land in [Song.contentMap] untouched; uses only decide
/// whether (and where) a known field gets UI.
enum SongFieldUse {
  /// Generic chip-row filter card over the field's own values.
  filterMultiselect(isFilterUse: true),

  /// Dedicated pitch/mode picker over the `key` column. App-side decision:
  /// bank overlays cannot introduce dedicated filter UI.
  filterKey(isFilterUse: true),

  /// Unified text search: FTS ∪ LIKE ∪ exact, tiered by relevance in SQL.
  /// Title and lyrics declare it too — they only differ in reading from
  /// dedicated columns instead of contentMap, which the FTS content view
  /// abstracts away. App-side decision like the dedicated filters: FTS
  /// columns are fixed at build time, so overlays can neither add nor drop
  /// search uses (see [mergeSongFields]).
  searchText(isSearchUse: true),

  /// Placeholder for scripture-reference search (e.g. "Jn 3,16"). When
  /// implemented, it will own bible-reference-shaped fields and its own
  /// query builder; until then no field declares it.
  searchBible(isSearchUse: true),

  /// Placeholder for songbook-number search (e.g. "234"). When implemented,
  /// exact songbook-number semantics move here from the text search's
  /// exact tier; until then no field declares it.
  searchSongbook(isSearchUse: true),

  /// Row in the song details list.
  details,

  /// Compact chip in the details summary.
  summary;

  const SongFieldUse({this.isFilterUse = false, this.isSearchUse = false});

  /// Whether this use is one of the filter-card uses.
  final bool isFilterUse;

  /// Whether this use is one of the search uses.
  final bool isSearchUse;
}

/// Definition of one song field in the shared bank vocabulary.
///
/// Field names are semantically global across banks: a bank should reuse an
/// existing name rather than define a near-duplicate, so one filter card
/// means the same thing everywhere. New fields usually start bank-defined
/// (via the bank's `songFields` metadata) and get promoted into
/// [defaultSongFields] as the vocabulary settles.
///
/// [core] fields back dedicated app features (identity, rendering,
/// transposition, assets) and may never be redefined by a bank overlay.
class SongField {
  final String apiName;
  final String title;
  final SongFieldType type;
  final IconData? icon;
  final Set<SongFieldUse> uses;

  /// Ranking group for the unified text search. Only meaningful together
  /// with a search use; null on fields the search never ranks. Parsed
  /// from bank metadata so future promotions can carry their declared
  /// group, but base definitions win in [mergeSongFields] — weighting
  /// the fixed FTS columns is an app-side decision.
  final SongSearchGroup? searchGroup;

  /// Mechanistic field with a dedicated column/feature. Immune to overlays.
  final bool core;

  const SongField(
    this.apiName,
    this.title,
    this.type, {
    this.icon,
    this.uses = const {},
    this.searchGroup,
    this.core = false,
  });

  bool hasUse(SongFieldUse use) => uses.contains(use);

  bool get hasFilterUse => uses.any((use) => use.isFilterUse);

  bool get hasSearchUse => uses.any((use) => use.isSearchUse);

  /// The one filter-card use this field has, or null when it has none.
  /// Used to dispatch the filter card UI.
  SongFieldUse? get filterUse {
    for (final use in uses) {
      if (use.isFilterUse) return use;
    }
    return null;
  }

  /// Parses one bank overlay entry from the bank metadata API. The endpoint
  /// is unpopulated so far, so this stays deliberately lenient: recognized
  /// keys are read, everything else is ignored, and values degrade to safe
  /// defaults rather than throwing.
  factory SongField.fromJson(String apiName, Map<String, dynamic> json) {
    final rawType = json['type'];
    final type = switch ((rawType is String ? rawType : '').toLowerCase()) {
      'list' || 'array' || 'tags' => SongFieldType.list,
      _ => SongFieldType.text,
    };
    final usesRaw = json['uses'];
    final uses = <SongFieldUse>{
      if (usesRaw is List)
        for (final use in usesRaw)
          if (use == 'filter_multiselect')
            SongFieldUse.filterMultiselect
          else if (use == 'filter_key')
            SongFieldUse.filterKey
          else if (use == 'details')
            SongFieldUse.details
          else if (use == 'summary')
            SongFieldUse.summary,
    };
    final rawGroup = json['search_group'];
    final group = rawGroup is String ? rawGroup : '';
    final searchGroup = switch (group.toLowerCase()) {
      'title' => SongSearchGroup.title,
      'people' => SongSearchGroup.people,
      'metadata' => SongSearchGroup.metadata,
      'lyrics' => SongSearchGroup.lyrics,
      _ => null,
    };
    final rawTitle = json['title'];
    return SongField(
      apiName,
      rawTitle is String ? rawTitle : apiName,
      type,
      searchGroup: searchGroup,
      uses: uses,
    );
  }
}

/// The app's working knowledge of the shared bank vocabulary at build time.
/// Order matters: it drives the display order in the details list.
const List<SongField> defaultSongFields = [
  // Mechanistic fields (dedicated columns/features; never overlay-defined).
  SongField('uuid', 'Azonosító', SongFieldType.text, core: true),
  SongField(
    'title',
    'Cím',
    SongFieldType.text,
    icon: Icons.text_fields,
    uses: {SongFieldUse.searchText},
    searchGroup: SongSearchGroup.title,
    core: true,
  ),
  SongField(
    'lyrics',
    'Dalszöveg',
    SongFieldType.text,
    icon: Icons.text_snippet,
    uses: {SongFieldUse.searchText},
    searchGroup: SongSearchGroup.lyrics,
    core: true,
  ),
  SongField(
    'key',
    'Hangnem',
    SongFieldType.list,
    icon: Icons.piano,
    uses: {SongFieldUse.filterKey},
    core: true,
  ),
  SongField('variation_of', 'Változata', SongFieldType.text, core: true),
  SongField('pdf', 'Kotta (PDF)', SongFieldType.text, core: true),
  SongField('svg', 'Kotta (SVG)', SongFieldType.text, core: true),

  // People and references: details rows and summary chips.
  SongField(
    'composer',
    'Dalszerző',
    SongFieldType.text,
    icon: Icons.music_note,
    uses: {SongFieldUse.details, SongFieldUse.summary, SongFieldUse.searchText},
    searchGroup: SongSearchGroup.people,
  ),
  SongField(
    'lyricist',
    'Szövegíró',
    SongFieldType.text,
    icon: Icons.edit,
    uses: {SongFieldUse.details, SongFieldUse.summary, SongFieldUse.searchText},
    searchGroup: SongSearchGroup.people,
  ),
  SongField(
    'translator',
    'Fordító',
    SongFieldType.text,
    icon: Icons.translate,
    uses: {SongFieldUse.details, SongFieldUse.summary, SongFieldUse.searchText},
    searchGroup: SongSearchGroup.people,
  ),
  SongField(
    'title_original',
    'Cím (eredeti)',
    SongFieldType.text,
    icon: Icons.wrap_text,
    uses: {SongFieldUse.details, SongFieldUse.searchText},
    searchGroup: SongSearchGroup.metadata,
  ),
  SongField(
    'bible_ref',
    'Igeszakasz',
    SongFieldType.text,
    icon: Icons.book,
    uses: {SongFieldUse.details, SongFieldUse.searchText},
    searchGroup: SongSearchGroup.metadata,
  ),
  SongField(
    'songbook',
    'Énekeskönyv',
    SongFieldType.text,
    icon: Icons.menu_book,
    uses: {SongFieldUse.details, SongFieldUse.searchText},
    searchGroup: SongSearchGroup.metadata,
  ),

  // Tag filters that also show as details rows.
  SongField(
    'language',
    'Eredeti nyelv',
    SongFieldType.text,
    icon: Icons.language,
    uses: {SongFieldUse.filterMultiselect, SongFieldUse.details},
  ),
  SongField(
    'genre',
    'Stílus / műfaj',
    SongFieldType.list,
    icon: Icons.style,
    uses: {SongFieldUse.filterMultiselect, SongFieldUse.details},
  ),
  SongField(
    'content_tags',
    'Tartalomcímkék',
    SongFieldType.list,
    icon: Icons.label_sharp,
    uses: {SongFieldUse.filterMultiselect, SongFieldUse.details},
  ),
  SongField(
    'holiday',
    'Ünnep',
    SongFieldType.list,
    icon: Icons.celebration,
    uses: {SongFieldUse.filterMultiselect, SongFieldUse.details},
  ),
  SongField(
    'book',
    'Sófár kottafüzet',
    SongFieldType.list,
    icon: Icons.calendar_month,
    uses: {SongFieldUse.filterMultiselect, SongFieldUse.details},
  ),

  // More details rows with their own filter cards.
  SongField(
    'instruments',
    'Hangszerek',
    SongFieldType.list,
    icon: Icons.piano_outlined,
    uses: {SongFieldUse.filterMultiselect, SongFieldUse.details},
  ),
  SongField(
    'time_signature',
    'Ütemmutató',
    SongFieldType.list,
    icon: Icons.timer,
    uses: {SongFieldUse.filterMultiselect, SongFieldUse.details},
  ),
  SongField(
    'liturgical_role',
    'Liturgiai szerep',
    SongFieldType.list,
    icon: Icons.church,
    uses: {SongFieldUse.filterMultiselect, SongFieldUse.details},
  ),
  SongField(
    'other_features',
    'Egyéb jellemzők',
    SongFieldType.list,
    icon: Icons.category,
    uses: {SongFieldUse.filterMultiselect, SongFieldUse.details},
  ),
  SongField(
    'dynamics',
    'Dinamika',
    SongFieldType.text,
    icon: Icons.graphic_eq,
    uses: {SongFieldUse.filterMultiselect, SongFieldUse.details},
  ),

  // Known vocabulary without UI yet: stored and synced, nothing displayed.
  SongField('link', 'Hivatkozások', SongFieldType.list),
  SongField('bpm', 'BPM', SongFieldType.text),
  SongField('changing_bpm', 'Változó BPM', SongFieldType.text),
  SongField('time', 'Időtartam', SongFieldType.text),
  SongField('year', 'Év', SongFieldType.text),
  SongField('lowest_note', 'Legmélyebb hang', SongFieldType.text),
  SongField('highest_note', 'Legmagasabb hang', SongFieldType.text),
  SongField('presentation', 'Vetítési sorrend', SongFieldType.text),
];

/// Lookup view over [defaultSongFields]. Final (not const): its
/// consumers pass it as a defaulting argument, which they do via
/// `registry ?? defaultSongFieldRegistry`.
final Map<String, SongField> defaultSongFieldRegistry = {
  for (final field in defaultSongFields) field.apiName: field,
};

/// Merges bank overlay metadata (from the bank's `songFields` about data)
/// over a base registry. Overlay entries may add new fields or customize
/// non-core ones; core fields are immune. Icons and dedicated filter
/// cards stay app-side. With empty overlays (the current state of the
/// ecosystem) this returns the base.
Map<String, SongField> mergeSongFields(
  Map<String, SongField> base,
  Map<String, dynamic> overlay,
) {
  if (overlay.isEmpty) return base;
  final merged = {...base};
  for (final entry in overlay.entries) {
    final baseDef = base[entry.key];
    if (baseDef != null && baseDef.core) continue;
    final json = entry.value;
    if (json is! Map<String, dynamic>) continue;
    final field = SongField.fromJson(entry.key, json);
    // An overlay that omits (or malforms) title/type keeps the base
    // definition's wording instead of degrading to the api name/text.
    final rawTitle = json['title'];
    final rawType = json['type'];
    merged[entry.key] = SongField(
      field.apiName,
      rawTitle is String ? rawTitle : (baseDef?.title ?? field.title),
      rawType is String ? field.type : (baseDef?.type ?? field.type),
      icon: baseDef?.icon,
      // Search ranking group follows the title/type pattern: the base
      // definition wins when the field is known, so overlays cannot
      // re-weight the fixed FTS columns. A group declared on an
      // overlay-introduced field is inert today (not in the FTS) but
      // carries over when the field is promoted into the defaults.
      searchGroup: baseDef?.searchGroup ?? field.searchGroup,
      // Dedicated filter cards are app-side decisions, like icons: only
      // the core `key` field may use the key picker, and it is immune to
      // overlays anyway, so a bank's filter_key never passes through.
      // Search uses are app-side too: FTS columns are fixed at build
      // time, so overlays keep the base definition's search uses, and
      // overlay-introduced fields are simply not full-text searchable.
      uses: {
        ...field.uses.where((use) => use != SongFieldUse.filterKey),
        ...?baseDef?.uses.where((use) => use.isSearchUse),
      },
    );
  }
  return merged;
}
