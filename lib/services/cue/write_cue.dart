import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/v4.dart';

import '../../data/cue/cue.dart';
import '../../data/cue/slide.dart';
import '../../data/database.dart';
import '../../ui/cue/session/session_provider.dart';

Future<Cue> insertNewCue({required String title, required String description}) {
  return db
      .into(db.cues)
      .insertReturning(
        CuesCompanion(
          id: Value.absent(),
          uuid: Value(UuidV4().generate()),
          title: Value(title),
          description: Value(description),
          cueVersion: Value(currentCueVersion),
          content: Value([]),
        ),
      );
}

Future<Cue> insertCueFromJson({required Map json}) {
  return db
      .into(db.cues)
      .insertReturning(
        CuesCompanion(
          id: Value.absent(),
          uuid: Value(json["uuid"]),
          title: Value(json["title"]),
          description: Value(json["description"]),
          cueVersion: Value(json["cueVersion"]),
          content: Value(
            (json["content"] as List).map((e) => e as Map).toList(),
          ),
        ),
      );
}

/// Overwrites the stored cue [json] describes (matched by uuid) and returns
/// the stored row. No UI or open-session handling; see [updateCueFromJson].
Future<Cue> overwriteCueRowFromJson(Map json) async {
  return (await (db.update(
        db.cues,
      )..where((c) => c.uuid.equals(json["uuid"]))).writeReturning(
        CuesCompanion(
          title: Value(json["title"]),
          description: Value(json["description"]),
          cueVersion: Value(json["cueVersion"]),
          content: Value(
            (json["content"] as List).map((e) => e as Map).toList(),
          ),
        ),
      ))
      .first;
}

Future<Cue> updateCueFromJson({
  required Map json,
  ProviderContainer? container,
  String? initialSlideUuid,
}) async {
  final cue = await overwriteCueRowFromJson(json);

  return reloadOpenCueSessionIfNeeded(
    updatedCue: cue,
    container: container,
    initialSlideUuid: initialSlideUuid,
  );
}

Future<Cue> reloadOpenCueSessionIfNeeded({
  required Cue updatedCue,
  ProviderContainer? container,
  String? initialSlideUuid,
}) async {
  final session = container?.read(activeCueSessionProvider).value;
  if (container != null &&
      session != null &&
      session.cue.uuid == updatedCue.uuid) {
    await container
        .read(activeCueSessionProvider.notifier)
        .load(
          updatedCue.uuid,
          initialSlideUuid: initialSlideUuid ?? session.currentSlideUuid,
          forceReload: true,
        );

    final reloadedSession = container.read(activeCueSessionProvider).value;
    if (reloadedSession != null &&
        reloadedSession.cue.uuid == updatedCue.uuid) {
      return reloadedSession.cue;
    }
  }

  return updatedCue;
}

Future updateCueMetadata(
  Cue cue, {
  String? title,
  String? description,
  WidgetRef? ref,
}) async {
  final session = ref?.read(activeCueSessionProvider).value;
  if (ref != null && session != null && session.cue.uuid == cue.uuid) {
    ref
        .read(activeCueSessionProvider.notifier)
        .updateMetadata(title: title, description: description);
    return;
  }

  cue.updateMetadata(title: title, description: description);
  await writeCue(cue);
}

/// Persist the current state of a cue.
///
/// This writes both metadata and serialized content from the same Cue object.
Future writeCue(Cue cue) async {
  await (db.update(db.cues)..where((c) => c.uuid.equals(cue.uuid))).write(
    CuesCompanion(
      title: Value(cue.title),
      description: Value(cue.description),
      cueVersion: Value(cue.cueVersion),
      content: Value(cue.content),
    ),
  );
}

/// Add slide to a cue.
///
/// Routes through session if cue is currently active (for proper state management
/// and debounced writes). Otherwise writes directly to DB.
///
/// [ref] is required to check if the cue is active in the session.
Future<void> addSlideToCue(
  Slide slide,
  Cue cue, {
  int? atIndex,
  required WidgetRef ref,
}) async {
  final session = ref.read(activeCueSessionProvider).value;

  if (session != null && session.cue.uuid == cue.uuid) {
    // Active cue: route through session (gets debounced write + UI update)
    ref
        .read(activeCueSessionProvider.notifier)
        .addSlide(slide, atIndex: atIndex);
  } else {
    // Inactive cue: direct DB write
    cue.addSlide(slide, atIndex: atIndex);
    await writeCue(cue);
  }
}

Future deleteCueWithUuid(String uuid) {
  return db.cues.deleteWhere((c) => c.uuid.equals(uuid));
}
