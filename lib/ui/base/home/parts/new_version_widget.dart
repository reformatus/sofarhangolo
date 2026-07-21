import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../config/config.dart';
import '../../../../services/app_version/check_new_version.dart';

class NewVersionWidget extends ConsumerWidget {
  const NewVersionWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newVersionProvider = ref.watch(checkNewVersionProvider);
    final newVersion = newVersionProvider.value;

    if (newVersion != null) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 7),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 400),
          child: Badge(
            child: Card(
              color: Color.lerp(
                Colors.blue,
                Theme.of(context).scaffoldBackgroundColor,
                0.8,
              ),
              child: SelectionArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Új verzió elérhető: '),
                          Text(
                            newVersion.versionNumber,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      subtitle: FutureBuilder(
                        future: PackageInfo.fromPlatform(),
                        builder: (context, packageInfo) {
                          if (packageInfo.data != null) {
                            return Text(
                              'Jelenlegi: ${packageInfo.data!.version}\nTelepítés forrása: ${packageInfo.data!.installerStore}',
                              style: TextStyle(fontStyle: FontStyle.italic),
                            );
                          } else {
                            return Text('\n...');
                          }
                        },
                      ),
                    ),
                    Divider(),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: 200),
                      child: Markdown(
                        data: newVersion.releaseNotesMd,
                        shrinkWrap: true,
                        onTapLink: (link, _, _) => launchUrl(Uri.parse(link)),
                      ),
                    ),
                    Divider(),
                    Padding(
                      padding: EdgeInsets.all(15),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton(
                            onPressed: () =>
                                launchUrl(newVersion.releaseInfoLink),
                            child: Text('Részletek'),
                          ),
                          if (storeLinkForCurrentPlatform != null) ...[
                            SizedBox(width: 5),
                            FilledButton(
                              onPressed: () => launchUrl(
                                Uri.parse(storeLinkForCurrentPlatform!),
                              ),
                              child: Text('Frissítés'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      return SizedBox.shrink();
    }
  }
}
