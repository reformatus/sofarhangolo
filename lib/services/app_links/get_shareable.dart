import '../../data/cue/cue.dart';
import '../../data/song/song.dart';
import 'share_links.dart';

Uri getShareableLinkFor<T>(T item) {
  if (item is Song) {
    return getShareableSongLink(item);
  } else if (item is Cue) {
    return getShareableCueLink(item);
  } else {
    throw Exception('${item.runtimeType} típusú elem nem megosztható!');
  }
}
