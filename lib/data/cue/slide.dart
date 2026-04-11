import 'package:uuid/uuid.dart';

import '../../services/song/from_uuid.dart';
import '../../ui/song/state.dart';
import '../song/song.dart';
import '../song/transpose.dart';
import 'cue.dart';

part 'slide_types/song_slide.dart';

sealed class Slide {
  String get title;
  String get preview;
  final String uuid;
  final String? comment;

  const Slide(this.uuid, this.comment);

  /// Create a copy with updated fields - override in subclasses
  Slide copyWith({String? comment});

  static Future<Slide> reviveFromJson(Map json, Cue parent) {
    switch (json['slideType']) {
      case 'song':
        return SongSlide.reviveFromJson(json, parent);
      default:
        return Future.sync(
          () => UnknownTypeSlide(json, json['uuid'], json['comment']),
        );
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Slide && other.uuid == uuid;
  }

  @override
  int get hashCode => uuid.hashCode;

  Map toJson();
}

class UnknownTypeSlide extends Slide {
  final Map json;

  @override
  String get title => 'Ismeretlen dia';

  @override
  String get preview => 'Ismeretlen diatípus: ${json['slideType']}';

  @override
  Map toJson() => json;

  @override
  UnknownTypeSlide copyWith({String? comment, Map? json}) =>
      UnknownTypeSlide(json ?? this.json, uuid, comment ?? this.comment);

  const UnknownTypeSlide(this.json, super.uuid, super.comment);
}
