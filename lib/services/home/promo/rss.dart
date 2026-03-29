import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:xml/xml.dart';

import '../../../data/log/logger.dart';
import '../../../config/config.dart';
import '../../http/dio_provider.dart';

part 'rss.g.dart';

class HomepageNewsItem {
  Uri? backgroundImgUri;
  Uri link;
  String title;

  HomepageNewsItem({
    required this.backgroundImgUri,
    required this.link,
    required this.title,
  });

  factory HomepageNewsItem.fromRssItem(XmlElement item) {
    try {
      final title = item.findElements('title').first.innerText;
      final linkText = item.findElements('link').first.innerText;
      final link = Uri.parse(linkText);

      Uri? backgroundImgUri;
      try {
        final featuredImageElement = item.findElements('featured_image').first;
        backgroundImgUri = Uri.parse(featuredImageElement.innerText);
      } catch (_) {}

      return HomepageNewsItem(
        title: title,
        link: link,
        backgroundImgUri: backgroundImgUri,
      );
    } catch (e, s) {
      log.warning('Invalid RSS news feed item!', e, s);
      rethrow;
    }
  }
}

class HomepageButtonItem {
  Uri link;
  String title;
  String? faIconName;
  String? iconName;

  HomepageButtonItem({
    required this.link,
    required this.title,
    this.faIconName,
    this.iconName,
  });

  factory HomepageButtonItem.fromRssItem(XmlElement item) {
    try {
      final title = item.findElements('title').first.innerText;
      final linkText = item.findElements('button_link').first.innerText;
      final link = Uri.parse(linkText);

      String? iconName;
      try {
        final iconNameElement = item.findElements('button_icon').first;
        iconName = iconNameElement.innerText;
      } catch (_) {}

      String? faIconName;
      try {
        final iconNameElement = item.findElements('button_fa_icon').first;
        faIconName = iconNameElement.innerText;
      } catch (_) {}

      return HomepageButtonItem(
        title: title,
        link: link,
        faIconName: faIconName,
        iconName: iconName,
      );
    } catch (e, s) {
      log.warning('Invalid RSS button item!', e, s);
      rethrow;
    }
  }
}

/*
  Inspired by rss_dart
*/
@Riverpod(keepAlive: true)
Future<List<HomepageNewsItem>> getNews(Ref ref) async {
  Response<String> response;
  try {
    final dio = ref.read(dioProvider);
    response = await dio.get<String>(appConfig.newsRss);
  } catch (e, s) {
    log.warning("Couldn't get news: Network error!", e, s);
    return [];
  }
  if (response.data == null) {
    log.warning("Couldn't get news: No response!");
    return [];
  }
  final XmlDocument feed;
  try {
    feed = XmlDocument.parse(response.data!);
  } catch (e, s) {
    log.warning("Couldn't parse news RSS XML!", e, s);
    return [];
  }
  try {
    final channel = feed.findAllElements('channel').first;
    final items = channel.findAllElements('item');

    final news = items
        .map((item) => HomepageNewsItem.fromRssItem(item))
        .toList();
    return news;
  } catch (e, s) {
    log.warning("Couldn't get news: Invalid RSS feed!", e, s);
    return [];
  }
}

@Riverpod(keepAlive: true)
Future<List<HomepageButtonItem>> getButtons(Ref ref) async {
  Response<String> response;
  try {
    final dio = ref.read(dioProvider);
    response = await dio.get<String>(appConfig.buttonsRss);
  } catch (e, s) {
    log.warning("Couldn't get buttons: Network error!", e, s);
    return [];
  }
  if (response.data == null) {
    log.warning("Couldn't get buttons: No response!");
    return [];
  }
  final XmlDocument feed;
  try {
    feed = XmlDocument.parse(response.data!);
  } catch (e, s) {
    log.warning("Couldn't parse buttons RSS XML!", e, s);
    return [];
  }
  try {
    final channel = feed.findAllElements('channel').first;
    final items = channel.findAllElements('item');

    final buttons = items
        .map((item) {
          try {
            return HomepageButtonItem.fromRssItem(item);
          } catch (_) {
            return null; // Skip invalid button items
          }
        })
        .where((button) => button != null)
        .cast<HomepageButtonItem>()
        .toList();
    return buttons;
  } catch (e, s) {
    log.warning("Couldn't get buttons: Invalid RSS feed!", e, s);
    return [];
  }
}
