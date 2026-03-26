import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'provider.dart';

//* we need ref like this. do we never need to log before having a ref??
Logger log = Logger.root;

/// Logs are until this is called!
// far future todo add write and rotate logs on disk
void initLogger(WidgetRef ref) {
  log.onRecord.listen((record) {
    if (kDebugMode) {
      print(record);
    }
    unawaited(
      Future(() {
        ref.read(logMessagesProvider.notifier).addRecord(record);
      }),
    );
  });
}
