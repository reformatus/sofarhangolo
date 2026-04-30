import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../config/config.dart';
import '../../../data/song/song.dart';
import '../../../services/assets/get_song_asset.dart';
import '../../../services/preferences/providers/general.dart';
import '../../common/error/card.dart';
import '../state.dart';

class SheetView extends ConsumerWidget {
  const SheetView.svg(this.song, {super.key}) : _viewType = SongViewType.svg;
  const SheetView.pdf(this.song, {super.key}) : _viewType = SongViewType.pdf;

  final SongViewType _viewType;
  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    assert(
      _viewType != SongViewType.lyrics && _viewType != SongViewType.chords,
    );

    final generalPrefs = ref.watch(generalPreferencesProvider);
    final Brightness sheetBrightness = switch (generalPrefs.sheetBrightness) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };

    final assetField = switch (_viewType) {
      SongViewType.svg => 'svg',
      SongViewType.pdf || _ => 'pdf',
    };
    final assetProvider = getSongAssetProvider(song, assetField);
    final asset = ref.watch(assetProvider);

    switch (asset) {
      case AsyncError(:final error, :final stackTrace):
        return Center(
          child: LErrorCard.fromError(
            error: error,
            stackTrace: stackTrace,
            title: 'Nem sikerült betölteni a kottaképet.',
            icon: Icons.music_note,
            onRetry: () => ref.invalidate(assetProvider),
          ),
        );
      case AsyncData(value: final assetResult):
        if (assetResult.data != null) {
          switch (_viewType) {
            case SongViewType.svg:
              return Theme(
                data: ThemeData.from(
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: appConfig.colors.seedColor,
                    primary: appConfig.colors.primaryColor,
                    brightness: sheetBrightness,
                    surface: sheetBrightness == Brightness.dark
                        ? Colors.black
                        : null,
                  ),
                ),
                child: Builder(
                  builder: (context) {
                    return Container(
                      color: sheetBrightness == Brightness.light
                          ? Theme.of(context).colorScheme.onPrimary
                          : generalPrefs.oledBlackBackground
                          ? Colors.black
                          : Theme.of(context).colorScheme.surface,
                      child: InteractiveViewer(
                        maxScale: double.infinity,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: SvgPicture.memory(
                            assetResult.data!,
                            colorFilter: sheetBrightness == Brightness.dark
                                ? ColorFilter.mode(
                                    Theme.of(context).colorScheme.onSurface,
                                    BlendMode.srcIn,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            case SongViewType.pdf || _:
              switch (sheetBrightness) {
                case Brightness.dark:
                  return ColorFiltered(
                    colorFilter: ColorFilter.matrix([
                      -1, 0, 0, 0, 255, // Red
                      0, -1, 0, 0, 255, // Green
                      0, 0, -1, 0, 255, // Blue
                      0, 0, 0, 1, 0, // Alpha
                    ]),
                    child: _PdfSheetAssetView(
                      sourceName: song.uuid,
                      data: assetResult.data!,
                    ),
                  );
                case Brightness.light:
                  return _PdfSheetAssetView(
                    sourceName: song.uuid,
                    data: assetResult.data!,
                  );
              }
          }
        } else {
          return Center(
            child: CircularProgressIndicator(value: assetResult.progress),
          );
        }
      default:
        return Center(child: const CircularProgressIndicator());
    }
  }
}

class _PdfSheetAssetView extends StatefulWidget {
  const _PdfSheetAssetView({required this.sourceName, required this.data});

  final String sourceName;
  final Uint8List data;

  @override
  State<_PdfSheetAssetView> createState() => _PdfSheetAssetViewState();
}

class _PdfSheetAssetViewState extends State<_PdfSheetAssetView> {
  late final PdfViewerController _controller;
  late PdfDocumentRefData _documentRef;
  late PdfViewerParams _viewerParams;

  @override
  void initState() {
    super.initState();
    _controller = PdfViewerController();
    _documentRef = _createDocumentRef();
    _viewerParams = _createViewerParams();
  }

  @override
  void didUpdateWidget(covariant _PdfSheetAssetView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.sourceName != oldWidget.sourceName ||
        !identical(widget.data, oldWidget.data)) {
      _documentRef = _createDocumentRef();
    }
  }

  PdfDocumentRefData _createDocumentRef() {
    final key = PdfDocumentRefKey(widget.sourceName, [
      identityHashCode(widget.data),
    ]);

    return PdfDocumentRefData(
      widget.data,
      sourceName: widget.sourceName,
      key: key,
    );
  }

  PdfViewerParams _createViewerParams() {
    return PdfViewerParams(
      backgroundColor: Colors.transparent,
      calculateInitialZoom: _calculatePdfInitialZoom,
      loadingBannerBuilder: _buildPdfLoadingBanner,
      pageDropShadow: null,
      scrollByMouseWheel: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PdfViewer(
      _documentRef,
      controller: _controller,
      params: _viewerParams,
    );
  }
}

Widget _buildPdfLoadingBanner(
  BuildContext context,
  int bytesDownloaded,
  int? totalBytes,
) {
  return const Center(child: CircularProgressIndicator());
}

double _calculatePdfInitialZoom(
  PdfDocument document,
  PdfViewerController controller,
  double fitZoom,
  double coverZoom,
) {
  return fitZoom;
}
