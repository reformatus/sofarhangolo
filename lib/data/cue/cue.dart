import 'dart:convert';

import 'package:drift/drift.dart';

import '../database.dart';
import 'slide.dart';

/*
  far future todo: self-hostable cue collaboration platforms
  far future todo: local network cue collaboration
 */

const currentCueVersion = 1;

@UseRowClass(Cue)
@TableIndex(name: 'cues_uuid', columns: {#uuid}, unique: true)
class Cues extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get title => text()();
  TextColumn get description => text()();
  IntColumn get cueVersion => integer()();

  TextColumn get content => text().map(const CueContentConverter())();
}

class Cue extends Insertable<Cue> {
  final int id;
  final String uuid;
  String title;
  String description;
  int cueVersion;

  final List<Map> _serializedContent;
  List<Slide>? _revivedSlides;

  static List<Map> _copyContent(Iterable<Map> content) {
    return content.map((entry) => Map<String, dynamic>.from(entry)).toList();
  }

  bool get isRevived => _revivedSlides != null;

  List<Map> get content => isRevived
      ? getContentMapFromSlides(_revivedSlides!)
      : _copyContent(_serializedContent);

  List<Slide> get slides {
    final slides = _revivedSlides;
    if (slides == null) {
      throw StateError('Cue slides accessed before revival.');
    }
    return List.unmodifiable(slides);
  }

  int get slideCount =>
      isRevived ? _revivedSlides!.length : _serializedContent.length;

  Future<List<Slide>> getRevivedSlides() async {
    if (_revivedSlides != null) {
      return slides;
    }

    final revived = await Future.wait(
      _serializedContent.map(
        (entry) => Slide.reviveFromJson(Map<String, dynamic>.from(entry), this),
      ),
    );
    _revivedSlides = revived;
    return slides;
  }

  static List<Map> getContentMapFromSlides(Iterable<Slide> slides) {
    return slides
        .map((slide) => Map<String, dynamic>.from(slide.toJson()))
        .toList();
  }

  Slide? slideByUuid(String uuid) {
    final slides = _revivedSlides;
    if (slides == null) return null;
    try {
      return slides.firstWhere((slide) => slide.uuid == uuid);
    } catch (_) {
      return null;
    }
  }

  bool hasSlide(String slideUuid) {
    final slides = _revivedSlides;
    if (slides != null) {
      return slides.any((slide) => slide.uuid == slideUuid);
    }

    return _serializedContent.any((entry) => entry['uuid'] == slideUuid);
  }

  void updateMetadata({String? title, String? description, int? cueVersion}) {
    if (title != null) this.title = title;
    if (description != null) this.description = description;
    if (cueVersion != null) this.cueVersion = cueVersion;
  }

  void replaceMetadata(Cue cue) {
    updateMetadata(
      title: cue.title,
      description: cue.description,
      cueVersion: cue.cueVersion,
    );
  }

  void replaceSlides(Iterable<Slide> slides) {
    _revivedSlides = List<Slide>.from(slides);
  }

  void updateSlide(Slide updated) {
    final slides = _revivedSlides;
    if (slides != null) {
      final index = slides.indexWhere((slide) => slide.uuid == updated.uuid);
      if (index == -1) {
        throw StateError('Cannot update missing slide: ${updated.uuid}');
      }
      slides[index] = updated;
      return;
    }

    final index = _serializedContent.indexWhere(
      (entry) => entry['uuid'] == updated.uuid,
    );
    if (index == -1) {
      throw StateError('Cannot update missing slide: ${updated.uuid}');
    }
    _serializedContent[index] = Map<String, dynamic>.from(updated.toJson());
  }

  void addSlide(Slide slide, {int? atIndex}) {
    final insertIndex = atIndex;
    final slides = _revivedSlides;

    if (slides != null) {
      slides.insert(insertIndex ?? slides.length, slide);
      return;
    }

    _serializedContent.insert(
      insertIndex ?? _serializedContent.length,
      Map<String, dynamic>.from(slide.toJson()),
    );
  }

  void removeSlide(String slideUuid) {
    final slides = _revivedSlides;
    if (slides != null) {
      slides.removeWhere((slide) => slide.uuid == slideUuid);
      return;
    }

    _serializedContent.removeWhere((entry) => entry['uuid'] == slideUuid);
  }

  /// Reorders slides to match a [ReorderableListView.onReorderItem] callback.
  ///
  /// [newIndex] is already adjusted for the item removed at [oldIndex], so
  /// it is the moved slide's final index and must be used as-is.
  void reorderSlides(int oldIndex, int newIndex) {
    final slides = _revivedSlides;
    if (slides != null) {
      final item = slides.removeAt(oldIndex);
      slides.insert(newIndex, item);
      return;
    }

    final item = _serializedContent.removeAt(oldIndex);
    _serializedContent.insert(newIndex, item);
  }

  Cue(
    this.id,
    this.uuid,
    this.title,
    this.description,
    this.cueVersion,
    List<Map> content,
  ) : _serializedContent = _copyContent(content);

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return CuesCompanion(
      id: Value(id),
      uuid: Value(uuid),
      title: Value(title),
      description: Value(description),
      cueVersion: Value(cueVersion),
      content: Value(content),
    ).toColumns(nullToAbsent);
  }

  Map<String, dynamic> toJson() {
    return {
      "uuid": uuid,
      "title": title,
      "description": description,
      "cueVersion": cueVersion,
      "content": content,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Cue && other.uuid == uuid;
  }

  @override
  int get hashCode => uuid.hashCode;
}

class CueContentConverter extends TypeConverter<List<Map>, String> {
  const CueContentConverter();

  @override
  List<Map> fromSql(String fromDb) {
    return (jsonDecode(fromDb) as List).cast<Map>();
  }

  @override
  String toSql(List<Map> value) {
    return jsonEncode(value);
  }
}
