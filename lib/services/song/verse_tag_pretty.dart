String getPrettyVerseTagFrom(String type, int? index, {String? label}) {
  if (label != null && label.trim().isNotEmpty) {
    return label.trim();
  }

  if (type.isEmpty) {
    if (index == null) {
      return '';
    }
    return '$index';
  }

  return [
    switch (type.toUpperCase()) {
      // TODO make configurable
      'V' => 'Versszak',
      'C' => 'Refrén',
      'R' => 'Refrén',
      'P' => 'Pre-Refrén',
      'B' => 'Bridge',
      'T' => 'Coda',
      _ => type,
    },
    if (index != null) '$index',
  ].join(' ');
}
