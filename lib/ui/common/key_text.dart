import '../../data/song/song.dart';

const Map<String, String> _pitchDisplayMap = {
  'C': 'C',
  'Cis/Des': 'C#/Db',
  'D': 'D',
  'Dis/Es': 'D#/Eb',
  'E': 'E',
  'F': 'F',
  'Fis/Ges': 'F#/Gb',
  'G': 'G',
  'Gis/As': 'G#/Ab',
  'A': 'A',
  'B': 'B',
  'H': 'H',
};

const Map<String, String> _modeDisplayMap = {
  'dur': 'dúr',
  'moll': 'moll',
  'dor': 'dór',
  'frig': 'fríg',
  'lid': 'líd',
  'mixolid': 'mixolíd',
  'harmonikus_moll': 'harmonikus moll',
  'harmonikus_moll_iv': 'harmonikus moll IV',
  'harmonikus_moll_v': 'harmonikus moll V',
  'magyar_moll': 'magyar moll',
  'eol': 'eol',
  'lokriszi': 'lokriszi',
};

String displayKeyPitch(String pitch) {
  return _pitchDisplayMap[pitch] ?? pitch;
}

String displayKeyMode(String mode) {
  return _modeDisplayMap[mode] ?? mode;
}

String displayKeyString(String key) {
  final parts = key.split('-');
  if (parts.length != 2) return key;
  return '${displayKeyPitch(parts[0])}-${displayKeyMode(parts[1])}';
}

String displayKeyField(KeyField? keyField) {
  if (keyField == null) return '';
  return '${displayKeyPitch(keyField.pitch)}-${displayKeyMode(keyField.mode)}';
}

String displayKeyFields(Iterable<KeyField> keyFields) {
  return keyFields.map(displayKeyField).join('\n');
}
