import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state.dart';

class SearchFieldSelectorColumn extends ConsumerWidget {
  const SearchFieldSelectorColumn({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availableFields = ref.watch(availableSearchFieldsProvider);
    final effectiveSearchFields = ref.watch(effectiveSearchFieldsProvider);

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
        switch (availableFields) {
          AsyncError(:final error) => ListTile(title: Text('$error')),
          // ignore: unused_local_variable
          AsyncValue(:final value?) => switch (effectiveSearchFields) {
            AsyncError(:final error) => ListTile(title: Text('$error')),
            AsyncValue(:final value?) => Column(
              children: availableFields.requireValue
                  .map((field) {
                    final selected = value.contains(field.field);
                    final disableUnselect = value.length < 2 && selected;

                    return CheckboxListTile(
                      title: Text(field.titleHu),
                      secondary: Icon(field.icon),
                      value: selected,
                      onChanged: disableUnselect
                          ? null
                          : (newValue) {
                              if (newValue == null) return;
                              if (newValue) {
                                ref
                                    .read(searchFieldsStateProvider.notifier)
                                    .addSearchField(field.field);
                              } else {
                                ref
                                    .read(searchFieldsStateProvider.notifier)
                                    .removeSearchField(field.field);
                              }
                            },
                    );
                  })
                  .toList(growable: false),
            ),
            _ => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
          _ => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ],
    );
  }
}
