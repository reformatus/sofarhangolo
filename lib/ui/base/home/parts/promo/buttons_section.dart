import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:sofarhangolo/ui/base/home/parts/promo/icon_map.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../services/home/promo/rss.dart';

class ButtonsSection extends ConsumerStatefulWidget {
  const ButtonsSection({super.key});

  @override
  ConsumerState<ButtonsSection> createState() => _ButtonsSectionState();
}

class _ButtonsSectionState extends ConsumerState<ButtonsSection> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buttons = ref.watch(getButtonsProvider);

    return AnimatedSwitcher(
      duration: Durations.medium3,
      child: buttons.when(
        data: (buttonItems) {
          // Hide the section if there are no button items
          if (buttonItems.isEmpty) {
            return const SizedBox.shrink(key: ValueKey('empty'));
          }

          return _buildButtonsSection(
            key: const ValueKey('buttons'),
            buttonItems: buttonItems,
          );
        },
        loading: () => _buildLoadingSection(key: const ValueKey('loading')),
        error: (_, _) => const SizedBox.shrink(key: ValueKey('error')),
      ),
    );
  }

  Widget _buildLoadingSection({Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.only(top: 5, bottom: 8),
      height: 53,
      child: const SizedBox.shrink(), // Just maintain the vertical space
    );
  }

  Widget _buildButtonsSection({
    Key? key,
    required List<HomepageButtonItem> buttonItems,
  }) {
    final children = buttonItems
        .map(
          (buttonItem) => Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _ButtonItem(buttonItem: buttonItem),
          ),
        )
        .toList();

    return Container(
      key: key,
      height: 53,
      padding: const EdgeInsets.only(top: 5, bottom: 8),
      child: FadingEdgeScrollView.fromScrollView(
        child: ListView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          children: children,
        ),
      ),
    );
  }
}

class _ButtonItem extends StatelessWidget {
  final HomepageButtonItem buttonItem;

  const _ButtonItem({required this.buttonItem});

  @override
  Widget build(BuildContext context) {
    // Try to get icon from DynamicIcons
    Widget? iconWidget;

    // TODO not a good practice to use dynamic icons based on name, these buttons should be fixed
    if (buttonItem.faIconName != null && buttonItem.faIconName!.isNotEmpty) {
      iconWidget = FaIcon(fontAwesomeIcons[buttonItem.faIconName!]);
    } else if (buttonItem.iconName != null && buttonItem.iconName!.isNotEmpty) {
      iconWidget = Icon(materialIcons[buttonItem.iconName!]);
    }

    // If we have an icon, use FilledButton.tonalIcon, otherwise use FilledButton.tonal
    if (iconWidget != null) {
      return FilledButton.tonalIcon(
        onPressed: () async {
          try {
            await launchUrl(buttonItem.link, mode: LaunchMode.inAppBrowserView);
          } catch (e) {
            // Handle error silently
          }
        },
        icon: iconWidget,
        label: Text(buttonItem.title),
      );
    } else {
      return FilledButton.tonal(
        onPressed: () async {
          try {
            await launchUrl(buttonItem.link, mode: LaunchMode.inAppBrowserView);
          } catch (e) {
            // Handle error silently
          }
        },
        child: Text(buttonItem.title),
      );
    }
  }
}
