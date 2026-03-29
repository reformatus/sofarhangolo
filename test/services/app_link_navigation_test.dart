import 'package:flutter_test/flutter_test.dart';
import 'package:sofar/data/cue/cue.dart';
import 'package:sofar/data/song/song.dart';
import 'package:sofar/services/app_links/navigation.dart';
import 'package:sofar/services/app_links/share_links.dart';
import 'package:sofar/ui/cue/cue_page_type.dart';

import '../harness/test_config.dart';

void main() {
  group('initialRouteFromAppUri', () {
    test('falls back to home for null and loading routes', () {
      expect(initialRouteFromAppUri(null, config: testAppConfig), '/home');
      expect(
        initialRouteFromAppUri(
          Uri.parse('https://test.example.com/web/loading'),
          config: testAppConfig,
        ),
        '/home',
      );
    });

    test('keeps direct web song routes under the deployed /web base path', () {
      expect(
        initialRouteFromAppUri(
          Uri.parse('https://test.example.com/web/song/song-123?view=lyrics'),
          config: testAppConfig,
        ),
        '/song/song-123?view=lyrics',
      );
    });

    test('normalizes launch song links to the in-app song route', () {
      expect(
        initialRouteFromAppUri(
          Uri.parse('https://test.example.com/launch/song/song-123'),
          config: testAppConfig,
        ),
        '/song/song-123',
      );
    });

    test('keeps cue import launch routes intact for later handling', () {
      expect(
        initialRouteFromAppUri(
          Uri.parse(
            'https://test.example.com/launch/cueData?data=abc&slide=slide-1',
          ),
          config: testAppConfig,
        ),
        '/launch/cueData?data=abc&slide=slide-1',
      );
    });

    test('accepts legacy custom-scheme song links', () {
      expect(
        initialRouteFromAppUri(
          Uri.parse('testlyric://launch/song/song-123'),
          config: testAppConfig,
        ),
        '/song/song-123',
      );
      expect(
        initialRouteFromAppUri(
          Uri.parse('testlyric:///launch/song/song-123'),
          config: testAppConfig,
        ),
        '/song/song-123',
      );
    });
  });

  group('cueRoutePath', () {
    test('builds cue editor route with optional slide query', () {
      expect(cueRoutePath('cue-123', CuePageType.edit), '/cue/cue-123/edit');
      expect(
        cueRoutePath('cue-123', CuePageType.edit, slideUuid: 'slide-1'),
        '/cue/cue-123/edit?slide=slide-1',
      );
    });

    test(
      'builds cue musician presentation route with optional slide query',
      () {
        expect(
          cueRoutePath('cue-123', CuePageType.musician),
          '/cue/cue-123/present/musician',
        );
        expect(
          cueRoutePath('cue-123', CuePageType.musician, slideUuid: 'slide-1'),
          '/cue/cue-123/present/musician?slide=slide-1',
        );
      },
    );
  });

  group('shareable links', () {
    test('song links point to the general launch route', () {
      final song = Song(
        uuid: 'song-123',
        title: 'Song',
        lyrics: 'Lyrics',
        keyField: const [],
        contentMap: const {},
      );

      expect(
        getShareableSongLink(song, config: testAppConfig).toString(),
        'https://test.example.com/launch/song/song-123',
      );
    });

    test('cue links point to the general launch route', () {
      final cue = Cue(1, 'cue-123', 'Cue', '', 1, const []);

      final link = getShareableCueLink(cue, config: testAppConfig).toString();

      expect(link, startsWith('https://test.example.com/launch/cueData?'));
      expect(link, contains('data='));
    });
  });
}
