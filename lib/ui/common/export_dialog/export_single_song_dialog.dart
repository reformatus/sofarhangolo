import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sofarhangolo/data/song/song.dart';

import '../../../data/log/logger.dart';

class ExportSingleSongDialog extends StatefulWidget {
  const ExportSingleSongDialog({required this.song, super.key});

  final Song song;

  @override
  State<ExportSingleSongDialog> createState() => _ExportSingleSongDialogState();
}

class _ExportSingleSongDialogState extends State<ExportSingleSongDialog> {
  bool _copySuccess = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AlertDialog(
      title: const Text('Dal letöltése'),
      scrollable: true,
      contentPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      backgroundColor: colorScheme.surfaceContainerHighest,
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                border: BoxBorder.fromLTRB(
                  top: BorderSide(
                    color: colorScheme.outline.withAlpha(60),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 20),

                  // Link text box with copy button
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: colorScheme.outline.withAlpha(80),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      color: colorScheme.surface,
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: SelectableText(
                                widget.song.lyrics.toString(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurface,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                textAlign: TextAlign.left,
                              ),
                            ),
                          ),
                          Container(
                            width: 1,
                            color: colorScheme.outline.withAlpha(80),
                          ),
                          Material(
                            color: Colors.transparent,
                            child: Tooltip(
                              message: 'Másolás',
                              child: InkWell(
                                onTap: () => _copyToClipboard(context),
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(8),
                                  bottomRight: Radius.circular(8),
                                ),
                                child: Container(
                                  width: 48,
                                  decoration: _copySuccess
                                      ? BoxDecoration(
                                          color: Colors.green.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: const BorderRadius.only(
                                            topRight: Radius.circular(8),
                                            bottomRight: Radius.circular(8),
                                          ),
                                        )
                                      : null,
                                  child: Icon(
                                    _copySuccess ? Icons.check : Icons.copy,
                                    size: 18,
                                    color: _copySuccess
                                        ? Colors.green
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Share button integrated into the dialog body
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _shareLink(context),
                      icon: const Icon(Icons.share, size: 20),
                      label: const Text('Megosztás'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.song.lyrics.toString()));
    if (mounted) {
      setState(() {
        _copySuccess = true;
      });
      // Reset the button state after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _copySuccess = false;
          });
        }
      });
    }
  }

  Future<void> _shareLink(BuildContext context) async {
    try {
      // TODO
      await SharePlus.instance.share(ShareParams(uri: new Uri(), subject: ''));
    } catch (e, s) {
      log.warning('Megosztás közben hiba lépett fel', e, s);
    }
  }
}
