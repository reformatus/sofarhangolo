part of '../slide.dart';

class SongSlide extends Slide {
  static String slideType = 'song';

  /// The song this slide references. Kept even when [song] is missing, so the
  /// slide can recover when the song reappears (bank update, download, undo).
  final String songUuid;

  /// Cached song content, or null when the song is not present on this device.
  ///
  /// Live content is resolved from `songContentProvider` at render time; this
  /// is the initial/offline fallback and the source for the synchronous
  /// [title]/[preview] getters.
  final Song? song;

  final SongViewType viewType;
  final SongTranspose? transpose;

  /// Content hash captured when the song was added to the cue. Kept even when
  /// [song] is missing, so content drift can be detected once it is available.
  final String? sharedContentHash;

  /// Title captured alongside [sharedContentHash], so a missing song can still
  /// be named in the UI.
  final String? sharedTitle;

  /// Whether the referenced song is missing on this device.
  bool get isMissing => song == null;

  /// Whether [live] differs from the content that was added to the cue.
  bool contentDiffersFrom(Song? live) =>
      live != null &&
      sharedContentHash != null &&
      live.contentHash != sharedContentHash;

  /// Whether [live] differs from what was added AND the change came from
  /// someone other than the user. A bank-owned song can only change through a
  /// bank update (editing copies to local first), so it is worth warning
  /// about; a local song can only have been changed by the user themselves,
  /// which needs no warning.
  bool contentChangedByOthers(Song? live) =>
      contentDiffersFrom(live) && live!.sourceBank != localBankUuid;

  @override
  String get title => song?.title ?? sharedTitle ?? 'Hiányzó dal';

  @override
  String get preview => song?.firstLine ?? '';

  SongSlide(
    super.uuid,
    this.songUuid,
    super.comment, {
    this.song,
    required this.viewType,
    this.transpose,
    this.sharedContentHash,
    this.sharedTitle,
  });

  /// Creates a new slide that adds [song] to a cue.
  factory SongSlide.from(
    Song song, {
    required SongViewType viewType,
    SongTranspose? transpose,
    String? comment,
  }) {
    return SongSlide(
      const Uuid().v4(),
      song.uuid,
      comment,
      song: song,
      viewType: viewType,
      transpose: transpose,
      sharedContentHash: song.contentHash,
      sharedTitle: song.title,
    );
  }

  /// A copy of this slide carrying fresh [song] content (or null when the song
  /// went missing). Cue structure and the shared metadata are preserved.
  SongSlide withSong(Song? fresh) => SongSlide(
    uuid,
    songUuid,
    comment,
    song: fresh,
    viewType: viewType,
    transpose: transpose,
    sharedContentHash: sharedContentHash,
    sharedTitle: sharedTitle ?? fresh?.title,
  );

  /// Re-points this slide at [song] (e.g. the local copy of the bank song),
  /// carrying the slide's view/transpose settings over and refreshing the
  /// shared metadata to [song]'s content.
  SongSlide retarget(Song song) => SongSlide(
    uuid,
    song.uuid,
    comment,
    song: song,
    viewType: viewType,
    transpose: transpose,
    sharedContentHash: song.contentHash,
    sharedTitle: song.title,
  );

  @override
  SongSlide copyWith({
    SongViewType? viewType,
    SongTranspose? transpose,
    String? comment,
  }) => SongSlide(
    uuid,
    songUuid,
    comment ?? this.comment,
    song: song,
    viewType: viewType ?? this.viewType,
    transpose: transpose ?? this.transpose,
    sharedContentHash: sharedContentHash,
    sharedTitle: sharedTitle,
  );

  /// Revives a slide from cue JSON. Total: never throws. A missing or malformed
  /// song yields a slide with `song == null` (rendered as an error), and an
  /// unknown view type falls back to lyrics.
  static Future<SongSlide> reviveFromJson(Map json, Cue parent) async {
    final songJson = json['song'];

    final songUuid =
        (songJson is Map ? songJson['uuid'] : null) as String? ??
        json['uuid'] as String? ??
        '';
    final sharedContentHash = (songJson is Map
        ? songJson['contentHash']
        : null) as String?;

    Song? song;
    if (songUuid.isNotEmpty) {
      song = await dbSongFromUuid(songUuid);
    }

    SongViewType viewType;
    final rawViewType = json['viewType'];
    viewType = rawViewType is String
        ? SongViewType.fromString(rawViewType)
        : SongViewType.lyrics;

    SongTranspose? transpose;
    final rawTranspose = json['transpose'];
    if (rawTranspose is Map) {
      try {
        transpose = SongTranspose.fromJson(
          Map<String, dynamic>.from(rawTranspose),
        );
      } catch (_) {
        transpose = null;
      }
    }

    return SongSlide(
      json['uuid'] as String? ?? '',
      songUuid,
      json['comment'] as String?,
      song: song,
      viewType: viewType,
      transpose: transpose,
      sharedContentHash: sharedContentHash,
      sharedTitle: json['title'] as String?,
    );
  }

  @override
  Map toJson() {
    return Map.fromEntries([
      MapEntry('uuid', uuid),
      MapEntry('slideType', slideType),
      MapEntry('song', {
        'uuid': songUuid,
        if (sharedContentHash != null) 'contentHash': sharedContentHash,
      }),
      MapEntry('viewType', viewType.name),
      if (sharedTitle != null) MapEntry('title', sharedTitle),
      if (transpose != null && transpose!.isNotEmpty)
        MapEntry('transpose', transpose!.toJson()),
      if (comment != null) MapEntry('comment', comment),
    ]);
  }
}
