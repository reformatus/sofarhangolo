import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../data/bank/bank.dart';
import '../../../../../config/config.dart';

class BankDetailsDialog extends ConsumerStatefulWidget {
  const BankDetailsDialog(this.bank, {super.key});

  final Bank bank;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _BankDetailsDialogState();
}

class _BankDetailsDialogState extends ConsumerState<BankDetailsDialog> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: EdgeInsets.all(10),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: appConfig.breakpoints.tabletFromWidth,
        ),
        child: Material(
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Hero(
                  tag: 'details-${widget.bank.uuid}',
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                            left: 10,
                            top: 10,
                            bottom: 10,
                          ),
                          child: SizedBox.square(
                            dimension: 54,
                            child: FittedBox(
                              child: widget.bank.logo != null
                                  ? Image.memory(widget.bank.logo!)
                                  : Icon(Icons.library_music),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListTile(
                            title: Text(
                              widget.bank.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            subtitle:
                                widget.bank.description != null &&
                                    widget.bank.description!.isNotEmpty
                                ? Text(
                                    widget.bank.description!,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  )
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: context.pop,
                                  icon: Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsetsGeometry.fromLTRB(14, 7, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (widget.bank.contactEmail != null &&
                              widget.bank.contactEmail!.isNotEmpty)
                            IconButton(
                              tooltip: 'Üzenetküldés',
                              onPressed: () => launchUrl(
                                Uri.parse('mailto:${widget.bank.contactEmail}'),
                              ),
                              icon: Icon(Icons.sms_outlined),
                            ),
                          if (widget.bank.aboutLink != null &&
                              widget.bank.aboutLink!.isNotEmpty)
                            IconButton(
                              tooltip:
                                  'További információ: ${widget.bank.aboutLink}',
                              onPressed: () =>
                                  launchUrl(Uri.parse(widget.bank.aboutLink!)),
                              icon: Icon(Icons.open_in_new),
                            ),
                        ],
                      ),
                      Text(
                        'Legutóbb frissült',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        widget.bank.lastUpdated != null
                            ? DateFormat(
                                'yyyy. MM. dd. HH:mm',
                              ).format(widget.bank.lastUpdated!.toLocal())
                            : 'Még nem volt frissítve',
                      ),
                      SizedBox(height: 10),
                      if (widget.bank.legal != null &&
                          widget.bank.legal!.isNotEmpty) ...[
                        Text(
                          'Jogi nyilatkozat',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          widget.bank.legal!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        SizedBox(height: 10),
                      ],
                      Text(
                        'Fejlesztés alatt...\nNézz vissza további daltárakkal kapcsolatos funkciókért később!',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
