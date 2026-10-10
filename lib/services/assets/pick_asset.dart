import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// File extensions accepted for each attachment field.
const Map<String, List<String>> assetFieldExtensions = {
  'svg': ['svg'],
  'pdf': ['pdf'],
};

/// Opens a file picker for the attachment [field] and returns the picked
/// file's bytes, or null when the user cancels.
Future<Uint8List?> pickAssetBytes(String field) async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: assetFieldExtensions[field] ?? const [],
  );
  if (file == null) return null;

  final bytes = await file.readAsBytes();
  return bytes.isEmpty ? null : bytes;
}
