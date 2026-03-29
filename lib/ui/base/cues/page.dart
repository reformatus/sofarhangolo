import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/cue/cue.dart';
import '../../../services/app_links/navigation.dart';
import '../../../services/cue/cues.dart';
import '../../common/centered_hint.dart';
import '../../common/error/card.dart';
import '../../cue/cue_page_type.dart';
import 'dialogs.dart';

class SetsPage extends ConsumerStatefulWidget {
  const SetsPage({super.key});

  @override
  ConsumerState<SetsPage> createState() => _SetsPageState();
}

class _SetsPageState extends ConsumerState<SetsPage> {
  @override
  Widget build(BuildContext context) {
    final cues = ref.watch(watchAllCuesProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Listáim')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            showDialog(
              context: context,
              builder: (context) => EditCueDialog(),
            ).then((createdCue) {
              if (!mounted) return;
              if (createdCue == null) return;
              createdCue as Cue;
              // ignore: use_build_context_synchronously
              context.push(cueRoutePath(createdCue.uuid, CuePageType.edit));
            }),
        label: Text('Új lista'),
        icon: Icon(Icons.add_box_outlined),
      ),
      body: switch (cues) {
        AsyncError(:final error, :final stackTrace) => Center(
          child: LErrorCard.fromError(
            error: error,
            stackTrace: stackTrace,
            title: 'Hová lettek a listák?',
            icon: Icons.error,
          ),
        ),
        AsyncLoading() => Center(child: CircularProgressIndicator()),
        AsyncValue(:final value!) =>
          value.isNotEmpty
              ? ListView(children: value.map((e) => CueTile(e)).toList())
              : Center(
                  child: CenteredHint(
                    'Adj hozzá egy listát a jobb alsó sarokban!',
                    iconData: Icons.add_box_outlined,
                  ),
                ),
      },
    );
  }
}

class CueTile extends StatelessWidget {
  const CueTile(this.cue, {super.key});

  final Cue cue;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(cue.title),
      subtitle: cue.description.isNotEmpty ? Text(cue.description) : null,
      onTap: () => context.push(cueRoutePath(cue.uuid, CuePageType.edit)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.edit_outlined),
            onPressed: () => showDialog(
              context: context,
              builder: (context) => EditCueDialog(cue: cue),
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline),
            // TODO refactor with showConfirmDialog
            onPressed: () => showDialog(
              context: context,
              builder: (context) => DeleteCueDialog(cue: cue),
            ),
          ),
        ],
      ),
    );
  }
}
