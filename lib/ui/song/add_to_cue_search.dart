import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/cue/cue.dart';
import '../../data/cue/slide.dart';
import '../../data/song/song.dart';
import '../../data/song/transpose.dart';
import '../../services/app_links/navigation.dart';
import '../../services/cue/cues.dart';
import '../../services/cue/write_cue.dart';
import '../../services/ui/messenger_service.dart';
import '../base/cues/dialogs.dart';
import '../common/error/card.dart';
import '../cue/cue_page_type.dart';
import 'state.dart';

/// A reusable widget that provides search functionality for adding songs to cues
class AddToCueSearch extends ConsumerStatefulWidget {
  const AddToCueSearch({
    required this.song,
    required this.isDesktop,
    required this.viewType,
    required this.transpose,
    super.key,
  });

  final Song song;
  final bool isDesktop;
  final SongViewType viewType;
  final SongTranspose transpose;

  @override
  ConsumerState<AddToCueSearch> createState() => _AddToCueSearchState();
}

class _AddToCueSearchState extends ConsumerState<AddToCueSearch> {
  @override
  void initState() {
    searchController = SearchController();
    super.initState();
  }

  late final SearchController searchController;
  @override
  Widget build(BuildContext context) {
    final cuesAsync = ref.watch(watchAllCuesProvider);

    Future<void> handleCueSelection(
      SearchController controller,
      Cue cue,
    ) async {
      controller.closeView('');

      Slide songSlide = SongSlide.from(
        widget.song,
        viewType: widget.viewType,
        transpose: widget.transpose,
      );
      await addSlideToCue(songSlide, cue, ref: ref);

      messengerService.showSnackBarReplacingCurrent(
        SnackBar(
          showCloseIcon: true,
          content: Text(
            '${widget.song.title} hozzáadva a listához: ${cue.title}',
          ),
          action: SnackBarAction(
            label: 'Ugrás',
            onPressed: () => context.push(
              cueRoutePath(
                cue.uuid,
                CuePageType.edit,
                slideUuid: songSlide.uuid,
              ),
            ),
          ),
          duration: const Duration(seconds: 5),
        ),
        forceHideAfter: const Duration(seconds: 5),
      );
    }

    List<Cue> filterCues(String searchText) {
      final cues = cuesAsync.hasValue ? cuesAsync.requireValue : <Cue>[];
      return cues
          .where(
            (cue) =>
                cue.title.toLowerCase().contains(searchText.toLowerCase()) ||
                cue.description.toLowerCase().contains(
                  searchText.toLowerCase(),
                ),
          )
          .toList();
    }

    return SearchAnchor(
      searchController: searchController,
      viewOnSubmitted: (value) async {
        if (value.isEmpty) return;

        final filteredCues = filterCues(value);
        if (filteredCues.isNotEmpty) {
          await handleCueSelection(searchController, filteredCues.first);
        }
      },
      builder: (context, controller) {
        if (!widget.isDesktop) {
          return FilledButton.tonalIcon(
            icon: Icon(Icons.playlist_add),
            label: Text('Listához adás'),
            onPressed: () => controller.openView(),
          );
        } else {
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 250),
            child: SearchBar(
              controller: controller,
              leading: Icon(Icons.playlist_add),
              hintText: 'Listához adás...',
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              elevation: WidgetStatePropertyAll(1),
              onTap: () => controller.openView(),
              onChanged: (_) => controller.openView(),
            ),
          );
        }
      },
      suggestionsBuilder: (context, controller) async {
        try {
          final filteredCues = filterCues(controller.text);

          if (!mounted) return [];

          if (cuesAsync.hasError) {
            return [
              LErrorCard.fromError(
                error: cuesAsync.error!,
                stackTrace: cuesAsync.stackTrace,
                title: 'Nem sikerült betölteni a listákat :(',
                icon: Icons.list,
              ),
            ];
          }

          if (cuesAsync.isLoading && !cuesAsync.hasValue) {
            return [
              ListTile(
                leading: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text('Listák betöltése...'),
              ),
            ];
          }

          return [
                if (controller.text.isEmpty || filteredCues.isEmpty)
                  ListTile(
                    leading: Icon(Icons.add),
                    title: Text(
                      [
                        'Hozzáadás új listához',
                        if (filteredCues.isEmpty &&
                            controller.text.isNotEmpty) ...[
                          ': ',
                          controller.text,
                        ],
                      ].join(),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize:
                            // ignore: use_build_context_synchronously
                            Theme.of(context).textTheme.bodyMedium?.fontSize,
                      ),
                    ),
                    onTap: () =>
                        showDialog(
                          context: context,
                          builder: (context) =>
                              EditCueDialog(prefilledTitle: controller.text),
                        ).then((createdCue) {
                          if (createdCue == null) return;
                          createdCue as Cue;
                          handleCueSelection(controller, createdCue);
                        }),
                  ),
              ]
              .followedBy(
                filteredCues.asMap().entries.map((cueEntry) {
                  final selected =
                      cueEntry.key == 0 && controller.text.isNotEmpty;
                  return ListTile(
                    selected: selected,
                    selectedTileColor: Theme.of(context).colorScheme.onPrimary,
                    title: Text(cueEntry.value.title),
                    subtitle: cueEntry.value.description.isNotEmpty
                        ? Text(
                            cueEntry.value.description.split('\n').first,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                          )
                        : null,
                    trailing: selected ? Icon(Icons.keyboard_return) : null,
                    onTap: () => handleCueSelection(controller, cueEntry.value),
                  );
                }),
              )
              .toList();
        } catch (error, stackTrace) {
          return [
            LErrorCard.fromError(
              error: error,
              stackTrace: stackTrace,
              title: 'Nem sikerült betölteni a listákat :(',
              icon: Icons.list,
            ),
          ];
        }
      },
    );
  }
}
