part of '../slide.dart';

class SongSlide extends Slide {
  static String slideType = 'song';
  final Song song;
  final SongViewType viewType;
  final SongTranspose? transpose;
  // future: List<Verse> verses override

  final bool contentDifferentFlag;

  @override
  SongSlide copyWith({
    SongViewType? viewType,
    SongTranspose? transpose,
    String? comment,
    bool? contentDifferentFlag,
  }) => SongSlide(
    uuid,
    song,
    comment ?? this.comment,
    viewType: viewType ?? this.viewType,
    transpose: transpose ?? this.transpose,
    contentDifferentFlag: contentDifferentFlag ?? this.contentDifferentFlag,
  );

  @override
  String get title => song.title;

  @override
  String get preview => song.firstLine ?? '';

  static Future<SongSlide> reviveFromJson(Map json, Cue parent) async {
    final songJson = Map<String, dynamic>.from(json['song'] as Map);
    var songResult = await getSongForSlideJson(songJson);

    SongViewType viewType = SongViewType.fromString(json['viewType']);
    SongTranspose? transpose = json.containsKey('transpose')
        ? SongTranspose.fromJson(
            Map<String, dynamic>.from(json['transpose'] as Map),
          )
        : null;

    SongSlide songSlide = SongSlide(
      json['uuid'],
      songResult.song,
      json.containsKey('comment') ? json['comment'] : null,
      viewType: viewType,
      transpose: transpose,
      contentDifferentFlag: songResult.contentDifferentFlag,
    );

    return songSlide;
  }

  @override
  Map toJson() {
    return Map.fromEntries([
      MapEntry('uuid', uuid),
      MapEntry('slideType', slideType),
      MapEntry('song', songOfSlideToJson(song)),
      MapEntry('viewType', viewType.name),
      if (transpose != null && transpose!.isNotEmpty)
        MapEntry('transpose', transpose!.toJson()),
      if (comment != null) MapEntry('comment', comment),
    ]);
  }

  factory SongSlide.from(
    Song song, {
    required SongViewType viewType,
    SongTranspose? transpose,
    String? comment,
  }) {
    var slideUuid = const Uuid().v4();
    return SongSlide(
      slideUuid,
      song,
      comment,
      viewType: viewType,
      transpose: transpose,
    );
  }

  SongSlide(
    super.uuid,
    this.song,
    super.comment, {
    required this.viewType,
    this.transpose,
    this.contentDifferentFlag = false,
  });
}

Future<({Song song, bool contentDifferentFlag})> getSongForSlideJson(
  Map json,
) async {
  Song song = (await dbSongFromUuid(json['uuid']))!;
  // far future todo: handle edge cases; reading from list file, from network, from bank, from local etc
  // TODO fix
  return (
    song: song,
    contentDifferentFlag: false, //song.contentHash == json['contentHash'],
  );
}

Map songOfSlideToJson(Song song) {
  return {'uuid': song.uuid, 'contentHash': song.contentHash};
}
