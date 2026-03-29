import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'present/musician/page.dart';
import '../common/error/card.dart';
import 'edit/page.dart';
import 'cue_page_type.dart';
import 'session/cue_session.dart';
import 'session/session_provider.dart';

/// Loader widget that initializes the cue and slide state before rendering any CuePage
class CueLoaderPage extends ConsumerStatefulWidget {
  const CueLoaderPage(
    this.uuid,
    this.pageType, {
    this.initialSlideUuid,
    super.key,
  });

  final String uuid;
  final CuePageType pageType;
  final String? initialSlideUuid;

  @override
  ConsumerState<CueLoaderPage> createState() => _CueLoaderPageState();
}

class _CueLoaderPageState extends ConsumerState<CueLoaderPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfNeeded());
  }

  @override
  void didUpdateWidget(covariant CueLoaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uuid != widget.uuid ||
        oldWidget.initialSlideUuid != widget.initialSlideUuid) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfNeeded());
    }
  }

  void _loadIfNeeded() {
    if (!mounted) return;

    final sessionAsync = ref.read(activeCueSessionProvider);
    final currentUuid = sessionAsync.value?.cue.uuid;

    if (currentUuid == widget.uuid) {
      if (widget.initialSlideUuid != null) {
        ref
            .read(activeCueSessionProvider.notifier)
            .load(widget.uuid, initialSlideUuid: widget.initialSlideUuid);
      }
      return;
    }
    ref
        .read(activeCueSessionProvider.notifier)
        .load(widget.uuid, initialSlideUuid: widget.initialSlideUuid);
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(activeCueSessionProvider);

    return sessionAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) => Scaffold(
        appBar: AppBar(title: const Text('Hiba')),
        body: Center(
          child: LErrorCard.fromError(
            error: error,
            stackTrace: stack,
            title: 'Nem sikerült betölteni a listát',
            icon: Icons.error,
          ),
        ),
      ),
      data: (session) {
        if (session == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return buildPage(session);
      },
    );
  }

  Widget buildPage(CueSession session) {
    switch (widget.pageType) {
      case CuePageType.edit:
        return CueEditPage(session);
      case CuePageType.musician:
        return CuePresentMusicianPage(session);
    }
  }
}
