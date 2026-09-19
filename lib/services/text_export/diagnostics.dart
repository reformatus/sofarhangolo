/// Default cap for stack trace lines in exported diagnostics.
const defaultMaxStackLines = 20;

/// Caps a stack trace to [maxLines] lines, noting how many were omitted.
String capStackLines(String? stack, {int maxLines = defaultMaxStackLines}) {
  if (stack == null || stack.isEmpty) return '';
  final lines = stack.split('\n');
  final capped = lines.take(maxLines).join('\n');
  if (lines.length <= maxLines) return capped;
  return '$capped\n… (${lines.length - maxLines} további sor)';
}

/// Formats an error's diagnostics for clipboard export and bug reports:
/// title, user-facing message and a line-capped stack trace.
String formatDiagnostics({
  String? title,
  String? message,
  String? stack,
  int maxStackLines = defaultMaxStackLines,
}) {
  return [
    if (title != null && title.isNotEmpty) title,
    if (message != null && message.isNotEmpty) message,
    if (stack != null && stack.isNotEmpty)
      capStackLines(stack, maxLines: maxStackLines),
  ].join('\n\n');
}

/// Formats a single log entry for clipboard export: severity, timestamp,
/// message, the underlying error and a line-capped stack trace.
String formatLogEntry({
  required String level,
  required DateTime time,
  required String message,
  Object? error,
  StackTrace? stackTrace,
  int maxStackLines = defaultMaxStackLines,
}) {
  final timestamp =
      '${time.year.toString().padLeft(4, '0')}-'
      '${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')} '
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
  return [
    '[$level $timestamp] $message',
    if (error != null) error.toString(),
    capStackLines(stackTrace?.toString(), maxLines: maxStackLines),
  ].where((part) => part.isNotEmpty).join('\n\n');
}
