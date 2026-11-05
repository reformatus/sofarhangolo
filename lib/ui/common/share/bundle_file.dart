import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../services/platform/platform_provider.dart';
import '../../../services/ui/messenger_service.dart';

/// Hands a `.sofar` song bundle over to the user.
///
/// - Mobile: the system share sheet (`SharePlus` supports files there).
/// - Desktop and web: a save dialog / browser download through `file_picker`
///   (the share sheet is not available on Linux, and a saved file is what
///   desktop users expect anyway).
Future<void> shareBundleFile({
  required PlatformInfo platform,
  required MessengerService messenger,
  required Uint8List bytes,
  required String fileName,
}) async {
  if (platform.isMobile && !platform.isWeb) {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/zip')],
        fileNameOverrides: [fileName],
      ),
    );
    return;
  }

  final saved = await FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: 'application/zip',
    dialogTitle: 'Dalfájl mentése',
  );
  // null: the user cancelled.
  if (saved != null) {
    messenger.showSnackBar(const SnackBar(content: Text('Fájl elmentve.')));
  }
}
