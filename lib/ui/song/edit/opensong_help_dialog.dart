import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/config.dart';
import '../../common/monospace.dart';

/// Opens the OpenSong format help, matching the app's other dialogs: a title
/// bar with a close button on the right, a scrollable body and the tablet
/// breakpoint as the maximum width.
Future<void> showOpenSongHelpDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => const OpenSongHelpDialog(),
  );
}

/// A detailed guide to the OpenSong lyrics format as this app reads and writes
/// it.
///
/// The wording follows `dart_opensong`, the package that parses the format, so
/// the documented behaviour is exactly what the preview and presentation
/// render. Kept in its own file so the lyrics editor stays focused on editing.
class OpenSongHelpDialog extends StatelessWidget {
  const OpenSongHelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(10),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: appConfig.breakpoints.tabletFromWidth,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBar(
              title: const Text('OpenSong formátum'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  onPressed: context.pop,
                  icon: const Icon(Icons.close),
                ),
              ],
              actionsPadding: const EdgeInsets.only(right: 8),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 20,
                  children: [
                    Text(
                      'A dalszöveg szakaszokból áll. Minden szakasz egy '
                      'szögletes zárójeles címkével kezdődik, egy saját sorban. '
                      'A sorok típusát az első karakterük dönti el.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const _HelpSection(
                      title: 'Szakaszcímkék',
                      children: [
                        Text(
                          'A címke betűkből és egy opcionális sorszámból áll: '
                          '[V1], [C], [B], [Intro], [Outro]… A VERSE, CHORUS '
                          'stb. szavak helyett a gyakorlatban a V (verze), C '
                          '(refrén), B (bridge), P (pre-chorus) rövidítéseket '
                          'használjuk. Címke nélküli sorok is a legutóbbi '
                          'szakaszhoz tartoznak.',
                        ),
                        _CodeBlock('[V1]\n Első sor\n\n[C]\n A refrén'),
                      ],
                    ),
                    const _HelpSection(
                      title: 'Akkordsorok',
                      children: [
                        Text(
                          'A ponttal (.) kezdődő sor akkordsor. Az akkordok '
                          'oszlopról oszlopra igazodnak a közvetlenül alatta '
                          'álló szövegsorhoz: a . utáni szóközök számítanak, a '
                          'pont maga nem. Az alábbi példában a C a „Szeret” S '
                          'fölött, a G az „az” a fölött van.',
                        ),
                        _CodeBlock('.C     G\n Szeret az Úr'),
                        Text(
                          'Egy szakasz állhat csak akkordsorokból is (pl. egy '
                          'bevezető [Intro]), és egymás után több akkordsor is '
                          'állhat. A csak szóközt tartalmazó akkordsorokat a '
                          'program figyelmen kívül hagyja.',
                        ),
                      ],
                    ),
                    const _HelpSection(
                      title: 'A szövegsorok vezető szóköze',
                      children: [
                        Text(
                          'Minden szövegsor kötelezően szóközzel kezdődik. Ha '
                          'hiányzik, a program szövegként értelmezi, de '
                          'figyelmeztet, mert akkordsor mellett ez érvénytelen '
                          'formátum. Ezt a szerkesztő a sor elhagyásakor '
                          'pótolja.',
                        ),
                        _CodeBlock(' Megáldott az Úr'),
                      ],
                    ),
                    const _HelpSection(
                      title: 'Kitartott szótagok és elválasztás',
                      children: [
                        Text(
                          'Az aláhúzás (_) a szótag részét képezi, de nem '
                          'jelenik meg: kitölti a helyet, hogy a szótag egy '
                          'hosszabb akkord alá essen. Az alábbi példában a C '
                          'akkord alatt a Hello szótag áll, a két aláhúzás '
                          'csak helykitöltő.',
                        ),
                        _CodeBlock('.C\n __Hello'),
                        Text(
                          'Ha egy akkordváltás egy szót kettévág, a program '
                          'automatikusan kötőjelet rajzol a két szótag közé. '
                          'Szóhatáron (szóköznél) nem keletkezik kötőjel: a '
                          'példában Sze és retem közé kerül kötőjel.',
                        ),
                        _CodeBlock('.C  D\n Szeretem'),
                      ],
                    ),
                    const _HelpSection(
                      title: 'Számozott sorok',
                      children: [
                        Text(
                          'Ha a szövegsor közvetlenül egy számjeggyel (1, 2, '
                          '3…) kezdődik, a szám a versszak sorszámát jelöli. A '
                          'azonos sorszámú sorok egy szakaszba kerülnek, így a '
                          '[V] címke 1-es és 2-es sorai külön [V1] és [V2] '
                          'versszakot alkotnak.',
                        ),
                        _CodeBlock(
                          '[V]\n1Első versszak\n.C G\n2Második versszak',
                        ),
                      ],
                    ),
                    const _HelpSection(
                      title: 'Megjegyzések, nyomtatási sorok',
                      children: [
                        Text(
                          'A pontosvesszővel (;) kezdődő sor megjegyzés: nem '
                          'szöveg, dőlt betűvel jelenik meg.',
                        ),
                        _CodeBlock(';itt kezdődik a refrén'),
                        Text(
                          'A mínusszal (-) kezdődő sor nyomtatási vagy nem '
                          'támogatott utasítás (oldaltörés, oszloptörés). A '
                          'program „Ismeretlen sortípus” jelzéssel jeleníti '
                          'meg, és nem dobja el.',
                        ),
                        _CodeBlock('-!!\n---'),
                      ],
                    ),
                    const _HelpSection(
                      title: 'Előadási jelölők',
                      children: [
                        Text(
                          'A függőleges vonal (|) a dia tördelését vezérli. '
                          'Egy | üres sort szúr be, kettő (||) új diát kezd. '
                          'Önmagukban nem szövegsorok.',
                        ),
                        _CodeBlock(' | \n Első sor\n\n ||\n Új dián'),
                      ],
                    ),
                    const _HelpSection(
                      title: 'Üres sorok és sorvégek',
                      children: [
                        Text(
                          'A csupa üres sor csak elválasztó, a program '
                          'kihagyja. A Windows-os \\r\\n sorvég (CRLF) is '
                          'elfogadott: a \\r nem kerül a szövegbe.',
                        ),
                        _CodeBlock(
                          '.  em            D             C\r\n A harcokban nem nekünk kell győznünk.',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One titled block of the guide, so every section is laid out the same way.
class _HelpSection extends StatelessWidget {
  const _HelpSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        ...children,
      ],
    );
  }
}

/// A monospace example that keeps the character columns of the format visible.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          code,
          style: monospaceTextStyle.copyWith(
            fontSize: 13,
            height: 1.4,
            color: colors.onSurface,
          ),
        ),
      ),
    );
  }
}
