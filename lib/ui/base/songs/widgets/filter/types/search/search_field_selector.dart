import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../../data/song/song_fields.dart';
import '../../../../../../../services/songs/filter.dart';
import 'state.dart';

class SearchFieldSelectorColumn extends ConsumerWidget {
  const SearchFieldSelectorColumn({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var searchFieldsState = ref.watch(searchFieldsStateProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Theme.of(context).hoverColor),
          child: Text(
            'Miben keressen?',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
        ...fullTextSearchFields.map((e) {
          final field = defaultSongFieldRegistry[e]!;
          return CheckboxListTile(
            title: Text(field.title),
            secondary: Icon(field.icon),
            value: searchFieldsState.contains(e),
            onChanged:
                (searchFieldsState.length < 2 && searchFieldsState.contains(e))
                // Make sure at least one column stays selected
                ? null
                : (value) {
                    if (value == null) return;
                    if (value) {
                      ref
                          .read(searchFieldsStateProvider.notifier)
                          .addSearchField(e);
                    } else {
                      ref
                          .read(searchFieldsStateProvider.notifier)
                          .removeSearchField(e);
                    }
                  },
          );
        }),
      ],
    );
  }
}
