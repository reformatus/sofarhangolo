import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sofarhangolo/data/song/extensions.dart';
import 'package:sofarhangolo/data/song/song.dart';
import 'package:sofarhangolo/ui/common/share/export_util.dart';

import '../../../data/log/logger.dart';
import '../../../services/platform/platform_provider.dart';
import '../../../services/ui/messenger_service.dart';
import '../error/card.dart';
import '../hero_dialog_route.dart';
import 'bundle_file.dart';
import 'fullscreen_qr_dialog.dart';

/// Offer to hand over a `.sofar` song bundle (local songs travel by file,
/// not by link) from a share dialog.
class ShareFileOption {
  const ShareFileOption({
    required this.fileName,
    required this.build,
    this.note,
  });

  /// Suggested file name, with extension.
  final String fileName;

  /// Builds the file's bytes when the user asks for it.
  final Future<Uint8List> Function() build;

  /// Short explanation shown above the button (why a file, not a link).
  final String? note;
}

/// Shows an adaptive share dialog with QR code and native sharing functionality.
///
/// [title] - The title displayed at the top of the dialog\
/// [description] - Optional description text below the title\
/// [sharedTitle] - The name/title of the item being shared\
/// [sharedDescription] - Optional description of the item being shared\
/// [sharedIcon] - Optional icon for the shared item\
/// [sharedLink] - The URL/link to be shared and displayed as QR code; null
/// hides the link and QR code altogether (local songs: a link would not open
/// on any other device)\
/// [fileShare] - Offers "Megosztás fájlként" for a `.sofar` bundle
Future<void> showShareDialog(
  BuildContext context, {
  required String title,
  String? description,
  required String sharedTitle,
  String? sharedDescription,
  IconData? sharedIcon,
  required Uri? sharedLink,
  Song? song,
  ShareFileOption? fileShare,
}) async {
  return showDialog<void>(
    context: context,
    builder: (context) => ShareDialog(
      title: title,
      description: description,
      sharedTitle: sharedTitle,
      sharedDescription: sharedDescription,
      sharedIcon: sharedIcon,
      sharedLink: sharedLink,
      song: song,
      fileShare: fileShare,
    ),
  );
}

class ShareDialog extends ConsumerStatefulWidget {
  const ShareDialog({
    required this.title,
    this.description,
    required this.sharedTitle,
    this.sharedDescription,
    this.sharedIcon,
    required this.sharedLink,
    this.song,
    this.fileShare,
    super.key,
  });

  final String title;
  final String? description;

  final String sharedTitle;
  final String? sharedDescription;
  final IconData? sharedIcon;
  final Uri? sharedLink;
  final Song? song;
  final ShareFileOption? fileShare;

  @override
  ConsumerState<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends ConsumerState<ShareDialog> {
  bool _copySuccess = false;
  bool _pdfSharing = false;
  bool _fileSharing = false;
  // TODO: expose the original/raw OpenSong lyrics format here (e.g. a
  // "Eredeti formátum másolása" action for power users). Decided 2026-09-18:
  // lyrics copy actions use the user-friendly format instead.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // No SelectionArea here: the link already has a dedicated copy button, and
    // selection areas around whole dialogs make taps and drags unreliable.
    final link = widget.sharedLink;
    final fileShare = widget.fileShare;
    final linkShareWidget = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Description if provided
          if (widget.description != null) ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 25, vertical: 15),
              child: Text(
                widget.description!,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],

          SingleChildScrollView(
            child: Container(
              padding: EdgeInsets.all(25),
              child: Column(
                children: [
                  // Shared item header
                  Row(
                    children: [
                      if (widget.sharedIcon != null) ...[
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            widget.sharedIcon,
                            size: 24,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.sharedTitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (widget.sharedDescription != null)
                              Text(
                                widget.sharedDescription!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  if (link != null) ...[
                    const SizedBox(height: 24),
                    if (link.toString().length < 2000)
                      Hero(
                        tag: 'ShareDialogQr',
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.outline.withAlpha(60),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withValues(
                                  alpha: 0.08,
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadiusGeometry.circular(12),
                            ),
                            clipBehavior: Clip.antiAlias,
                            elevation: 0,
                            child: Tooltip(
                              message: 'Kód nagyítása',
                              child: InkWell(
                                onTap: () => _showFullscreenQr(context),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: SizedBox.square(
                                    dimension: 200,
                                    child: QrImageView(
                                      data: link.toString(),
                                      version: QrVersions.auto,
                                      gapless: true,
                                      errorCorrectionLevel:
                                          QrErrorCorrectLevel.L,
                                      errorStateBuilder: (context, error) {
                                        return LErrorCard.fromError(
                                          error:
                                              error ??
                                              StateError(
                                                'A QR kód generálása sikertelen.',
                                              ),
                                          icon: Icons.qr_code,
                                          title: 'Nem tudunk QR kódot mutatni - helyette küldd el a linket közvetlenül:',
                                          showReportButton: false,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Text(
                        'Ez a link túl hosszú QR kódos megosztáshoz. Helyette küldd tovább a linket közvetlenül:',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),

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
                                child: Text(
                                  link.toString(),
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
                                            borderRadius:
                                                const BorderRadius.only(
                                                  topRight: Radius.circular(8),
                                                  bottomRight: Radius.circular(
                                                    8,
                                                  ),
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
                  if (fileShare != null) ...[
                    const SizedBox(height: 20),
                    if (fileShare.note != null) ...[
                      Text(
                        fileShare.note!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: link == null
                          ? FilledButton.icon(
                              key: const ValueKey('share-file'),
                              onPressed: _fileSharing ? null : _shareFile,
                              icon: const Icon(Icons.attach_file, size: 20),
                              label: const Text('Megosztás fájlként'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            )
                          : OutlinedButton.icon(
                              key: const ValueKey('share-file'),
                              onPressed: _fileSharing ? null : _shareFile,
                              icon: const Icon(Icons.attach_file, size: 20),
                              label: const Text('Megosztás fájlként'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final List<Widget> shareWidgets = [];
    final song = widget.song;
    if (song != null) {
      if (song.pdfRef != null) {
        shareWidgets.add(
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _pdfSharing ? null : () => _sharePdf(song),
              child: _pdfSharing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('PDF'),
            ),
          ),
        );
      }

      if (song.hasLyrics) {
        shareWidgets.add(
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => shareLyricsText(song),
              child: const Text('Dalszöveg'),
            ),
          ),
        );
        // The raw source doubles as the original-format export; the label
        // notes whether it includes chords.
        shareWidgets.add(
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => shareRawLyrics(song),
              child: Text(
                song.hasChords
                    ? 'Dalszöveg (eredeti formátum akkordokkal)'
                    : 'Dalszöveg (eredeti formátum)',
              ),
            ),
          ),
        );
        // TODO copy transposed
      }
    }

    return DefaultTabController(
      length: 2,
      child: AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text(widget.title)),
            IconButton(
              onPressed: context.pop,
              icon: const Icon(Icons.close),
              style: IconButton.styleFrom(
                minimumSize: const Size(24, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        scrollable: true,
        contentPadding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        backgroundColor: colorScheme.surfaceContainerHighest,
        content: SizedBox(
          width: 320,
          height: 600,
          child: widget.song == null || shareWidgets.isEmpty
              ? linkShareWidget
              : Column(
                  children: [
                    TabBar(
                      tabs: [
                        SizedBox(
                          height: 25,
                          child: Text(link == null ? 'Fájl' : 'Link'),
                        ),
                        const SizedBox(height: 25, child: Text('Kotta')),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          Tab(child: linkShareWidget),
                          Tab(
                            child: ListView(
                              padding: EdgeInsets.all(10),
                              children: shareWidgets,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _sharePdf(Song song) async {
    if (_pdfSharing) return;
    setState(() => _pdfSharing = true);
    try {
      await sharePdf(song);
    } finally {
      if (mounted) setState(() => _pdfSharing = false);
    }
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    final link = widget.sharedLink;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link.toString()));
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

  Future<void> _showFullscreenQr(BuildContext context) async {
    final link = widget.sharedLink;
    if (link == null) return;
    showHeroDialog(
      context: context,
      builder: (context) => FullscreenQrDialog(data: link.toString()),
    );
  }

  Future<void> _shareLink(BuildContext context) async {
    final link = widget.sharedLink;
    if (link == null) return;
    try {
      await SharePlus.instance.share(
        ShareParams(uri: link, subject: widget.sharedTitle),
      );
    } catch (e, s) {
      log.warning('Megosztás közben hiba lépett fel', e, s);
    }
  }

  Future<void> _shareFile() async {
    final option = widget.fileShare;
    if (option == null || _fileSharing) return;
    setState(() => _fileSharing = true);
    final platform = ref.read(platformInfoProvider);
    final messenger = ref.read(messengerServiceProviderProvider);
    try {
      final bytes = await option.build();
      await shareBundleFile(
        platform: platform,
        messenger: messenger,
        bytes: bytes,
        fileName: option.fileName,
      );
    } catch (e, s) {
      log.warning('Fájl készítése közben hiba lépett fel', e, s);
      messenger.showSnackBar(
        const SnackBar(content: Text('Nem sikerült elkészíteni a fájlt.')),
      );
    } finally {
      if (mounted) setState(() => _fileSharing = false);
    }
  }
}
