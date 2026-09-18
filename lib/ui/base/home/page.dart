import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/log/button.dart';
import '../../../services/preferences/providers/general.dart';
import 'parts/banks/bank_chooser.dart';
import 'parts/new_version_widget.dart';
import 'parts/preferences/dialog.dart';
import 'parts/promo/buttons_section.dart';
import 'parts/promo/news_carousel.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  Widget build(BuildContext context) {
    final testingMode = ref.watch(generalPreferencesProvider).testingMode;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText('Sófár Hangoló'),
            if (testingMode) ...[
              SizedBox(width: 10),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Text(
                    'Teszt mód',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          LogButton(),
          IconButton(
            onPressed: () => showDialog(
              context: context,
              builder: (context) => PreferencesDialog(),
            ),
            icon: Icon(Icons.settings_outlined),
            tooltip: 'Beállítások',
          ),
        ],
      ),
      body: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 900),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Theme.of(context).colorScheme.onPrimary,
                  elevation: 3,
                  child: AnimatedSize(
                    duration: Durations.medium4,
                    curve: Curves.easeInOut,
                    child: Column(
                      children: [
                        NewVersionWidget(),
                        NewsCarousel(),
                        ButtonsSection(),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 8),
                BankChooser(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
