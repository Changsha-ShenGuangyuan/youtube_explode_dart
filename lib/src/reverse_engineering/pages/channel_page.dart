import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import '../../../youtube_explode_dart.dart';
import '../../exceptions/exceptions.dart';
import '../../extensions/helpers_extension.dart';
import '../../retry.dart';
import '../models/initial_data.dart';
import '../models/youtube_page.dart';
import '../youtube_http_client.dart';

///
class ChannelPage extends YoutubePage<_InitialData> {
  ///yfq修改增加原始数据返回
  JsonMap get rawMap => initialData.root;

  ///yfq修改增加原始数据返回---

  ///yfq 解析歌单列表数据
  List<Playlist> get playlists {
    var playlistContents = rawMap
        .get('contents')
        ?.get('twoColumnBrowseResultsRenderer')
        ?.getList('tabs')
        ?.firstWhere((e) => e['tabRenderer']?['title'] == 'Playlists',
            orElse: () => {})
        .get('tabRenderer')
        ?.get('content')
        ?.get('sectionListRenderer')
        ?.getList('contents')
        ?.firstOrNull
        ?.get('itemSectionRenderer')
        ?.getList('contents')
        ?.firstOrNull
        ?.get('gridRenderer')
        ?.getList('items');
    if (playlistContents == null) {
      return [];
    }

    List<Playlist> playlists = [];

    for (var item in playlistContents) {
      if (item['lockupViewModel'] != null) {
        final viewModel = item.get('lockupViewModel')!;

        final type = viewModel.getT<String>('contentType');
        if (type != 'LOCKUP_CONTENT_TYPE_PLAYLIST') {
          continue;
        }

        String? playlistId = viewModel.getT<String>('contentId');
        String? title = viewModel
            .getJson<String>('metadata/lockupMetadataViewModel/title/content');

        //     final thumbnails = viewModel
        //     .getJson<List<dynamic>>(
        //         'contentImage/collectionThumbnailViewModel/primaryThumbnail/thumbnailViewModel/image/sources')
        //     ?.cast<Map<String, dynamic>>();
        // List<Thumbnail> tht = thumbnails
        //         ?.map((e) =>
        //             Thumbnail(Uri.parse(e['url']), e['height'], e['width']))
        //         .toList() ??
        //     [];

        final playlistThumbnails = viewModel
            .getJson<List<dynamic>>(
                'contentImage/collectionThumbnailViewModel/primaryThumbnail/thumbnailViewModel/image/sources')
            ?.cast<Map<String, dynamic>>()
            .map((e) => Thumbnail(
                Uri.parse(e['url'] as String), e['height'] as int, e['width'] as int))
            .toList();

        int videoCount = viewModel
                .getJson<String>(
                    'contentImage/collectionThumbnailViewModel/primaryThumbnail/thumbnailViewModel/overlays/0/thumbnailOverlayBadgeViewModel/thumbnailBadges/0/thumbnailBadgeViewModel/text')
                ?.parseInt() ??
            0;

        final videoId = viewModel.getJson<String>(
            'rendererContext/commandContext/onTap/innertubeCommand/watchEndpoint/videoId');

        if (videoId == null ||
            title == null ||
            playlistId == null ||
            videoId.isEmpty ||
            title.isEmpty ||
            playlistId.isEmpty) {
          continue;
        }

        Playlist playlist = Playlist(
          PlaylistId(playlistId),
          title,
          '',
          '',
          ThumbnailSet(videoId),
          Engagement(videoCount, null, null),
          videoCount,
          playlistThumbnails: playlistThumbnails,
        );

        playlists.add(playlist);
      }
    }

    return playlists;
  }

  ///yfq 解析发布作品列表数据
  List<Playlist> get releaseLists {
    // 1. 尝试标准 Releases tab (richGridRenderer/playlistRenderer)
    var playlistContents = rawMap
        .get('contents')
        ?.get('twoColumnBrowseResultsRenderer')
        ?.getList('tabs')
        ?.firstWhere((e) => e['tabRenderer']?['title'] == 'Releases',
            orElse: () => {})
        .get('tabRenderer')
        ?.get('content')
        ?.get('richGridRenderer')
        ?.getList('contents');

    if (playlistContents != null) {
      final parsed = _parseReleaseFromPlaylistRenderer(playlistContents);
      if (parsed.isNotEmpty) return parsed;
    }

    // 2. 兼容 Topic 频道：Home tab 下 shelfRenderer 中的 lockupViewModel
    final topicItems = _getTopicReleaseLockups();
    if (topicItems.isNotEmpty) {
      return _parseReleaseFromLockupViewModel(topicItems);
    }

    return [];
  }

  /// 从标准 Releases tab 的 playlistRenderer 解析专辑列表
  List<Playlist> _parseReleaseFromPlaylistRenderer(
      List<Map<String, dynamic>> contents) {
    List<Playlist> playlists = [];

    for (var item in contents) {
      if (item['richItemRenderer'] == null) continue;

      Map<String, dynamic>? playlistRenderer =
          item.getJson<Map<String, dynamic>>(
              'richItemRenderer/content/playlistRenderer');
      if (playlistRenderer == null) continue;

      String? playlistId = playlistRenderer.getT<String>('playlistId');
      String? title =
          playlistRenderer.getJson<String>('title/simpleText');

      final playlistThumbnails = playlistRenderer
          .getJson<List<dynamic>>('thumbnails/0/thumbnails')
          ?.cast<Map<String, dynamic>>()
          .map((e) => Thumbnail(
              Uri.parse(e['url'] as String),
              e['height'] as int,
              e['width'] as int))
          .toList();

      int videoCount =
          playlistRenderer.getT<String>('videoCount')?.parseInt() ?? 0;
      String? author =
          playlistRenderer.getJson<String>('shortBylineText/runs/0/text');

      final videoId = playlistRenderer
          .getJson<String>('videos/0/childVideoRenderer/videoId');

      if (videoId == null ||
          title == null ||
          playlistId == null ||
          videoId.isEmpty ||
          title.isEmpty ||
          playlistId.isEmpty) {
        continue;
      }

      playlists.add(Playlist(
        PlaylistId(playlistId),
        title,
        author ?? '',
        '',
        ThumbnailSet(videoId),
        Engagement(videoCount, null, null),
        videoCount,
        playlistThumbnails: playlistThumbnails,
      ));
    }

    return playlists;
  }

  /// 从 Topic 频道主页 Home tab 的 shelfRenderer 中提取
  /// lockupViewModel 列表（Albums & Singles）
  List<Map<String, dynamic>> _getTopicReleaseLockups() {
    final tabs = rawMap
        .get('contents')
        ?.get('twoColumnBrowseResultsRenderer')
        ?.getList('tabs');
    if (tabs == null) return [];

    // 遍历所有 tab，优先查找 Home/featured tab
    for (final tab in tabs) {
      final sections = tab
          .get('tabRenderer')
          ?.get('content')
          ?.get('sectionListRenderer')
          ?.getList('contents');
      if (sections == null) continue;

      for (final section in sections) {
        final shelf =
            section.get('itemSectionRenderer')?.getList('contents');
        if (shelf == null) continue;

        for (final shelfItem in shelf) {
          final items = shelfItem
              .get('shelfRenderer')
              ?.get('content')
              ?.get('horizontalListRenderer')
              ?.getList('items');
          if (items == null || items.isEmpty) continue;

          // 检查第一个 item 是否是 ALBUM 类型的 lockupViewModel
          final firstType = items.first
              .get('lockupViewModel')
              ?.getT<String>('contentType');
          if (firstType == 'LOCKUP_CONTENT_TYPE_ALBUM') {
            return items;
          }
        }
      }
    }
    return [];
  }

  /// 从 lockupViewModel 格式解析专辑数据（Topic 频道使用此格式）
  List<Playlist> _parseReleaseFromLockupViewModel(
      List<Map<String, dynamic>> items) {
    List<Playlist> playlists = [];

    for (var item in items) {
      final viewModel = item.get('lockupViewModel');
      if (viewModel == null) continue;

      final type = viewModel.getT<String>('contentType');
      if (type != 'LOCKUP_CONTENT_TYPE_ALBUM') continue;

      String? playlistId = viewModel.getT<String>('contentId');
      String? title = viewModel.getJson<String>(
          'metadata/lockupMetadataViewModel/title/content');

      final playlistThumbnails = viewModel
          .getJson<List<dynamic>>(
              'contentImage/collectionThumbnailViewModel/'
              'primaryThumbnail/thumbnailViewModel/image/sources')
          ?.cast<Map<String, dynamic>>()
          .map((e) => Thumbnail(
              Uri.parse(e['url'] as String),
              e['height'] as int,
              e['width'] as int))
          .toList();

      // 从 badge 提取歌曲数量，格式如 "8 songs"
      int videoCount = viewModel
              .getJson<String>(
                  'contentImage/collectionThumbnailViewModel/'
                  'primaryThumbnail/thumbnailViewModel/overlays/0/'
                  'thumbnailOverlayBadgeViewModel/thumbnailBadges/0/'
                  'thumbnailBadgeViewModel/text')
              ?.parseInt() ??
          0;

      // 提取作者名
      String? author = viewModel.getJson<String>(
          'metadata/lockupMetadataViewModel/metadata/'
          'contentMetadataViewModel/metadataRows/0/'
          'metadataParts/0/text/content');

      // 从 watchEndpoint 提取首个视频 ID
      final videoId = viewModel.getJson<String>(
          'rendererContext/commandContext/onTap/'
          'innertubeCommand/watchEndpoint/videoId');

      if (title == null ||
          playlistId == null ||
          title.isEmpty ||
          playlistId.isEmpty) {
        continue;
      }

      playlists.add(Playlist(
        PlaylistId(playlistId),
        title,
        author ?? '',
        '',
        ThumbnailSet(videoId ?? ''),
        Engagement(videoCount, null, null),
        videoCount,
        playlistThumbnails: playlistThumbnails,
      ));
    }

    return playlists;
  }

  ///订阅数据
  String? get subscribers {
    List? rows = rawMap.getJson<List>(
        'header/pageHeaderRenderer/content/pageHeaderViewModel/metadata/contentMetadataViewModel/metadataRows');
    if (rows != null && rows.length > 1) {
      if (rows[1] is Map<String, dynamic>) {
        var list = (rows[1] as Map<String, dynamic>).getList("metadataParts");
        if (list != null && list.isNotEmpty) {
          String? value = list[0].get("text")?.getT<String>("content");
          if (value != null && value.contains("subscribers")) {
            return value;
          }
        }
      }
    }
    return null;
  }

  ///视频数
  int? get videoCounts {
    List? rows = rawMap.getJson<List>(
        'header/pageHeaderRenderer/content/pageHeaderViewModel/metadata/contentMetadataViewModel/metadataRows');
    if (rows != null && rows.length > 1) {
      if (rows[1] is Map<String, dynamic>) {
        var list = (rows[1] as Map<String, dynamic>).getList("metadataParts");
        if (list != null && list.length > 1) {
          String? value = list[1].get("text")?.getT<String>("content");
          if (value != null && value.contains("videos")) {
            value = value.replaceAll("videos", "");
            int? count = int.tryParse(value);
            if (count != null) {
              return count;
            }
          }
        }
      }
    }
    return null;
  }

  ///yfq修改---

  ///
  bool get isOk => root!.querySelector('meta[property="og:url"]') != null;

  ///
  String get channelUrl =>
      root!.querySelector('meta[property="og:url"]')?.attributes['content'] ??
      '';

  ///
  String get channelId => channelUrl.substringAfter('channel/');

  ///
  String get channelTitle =>
      root!.querySelector('meta[property="og:title"]')?.attributes['content'] ??
      '';

  ///
  String get channelLogoUrl =>
      root!.querySelector('meta[property="og:image"]')?.attributes['content'] ??
      '';

  String get channelBannerUrl => initialData.bannerUrl ?? '';

  int? get subscribersCount => initialData.subscribersCount;

  ///
  ChannelPage.parse(String raw)
      : super(parser.parse(raw), (root) => _InitialData(root));

  ///
  static Future<ChannelPage> get(YoutubeHttpClient httpClient, String id) {
    final url = 'https://www.youtube.com/channel/$id?hl=en';

    return retry(httpClient, () async {
      final raw = await httpClient.getString(url);
      final result = ChannelPage.parse(raw);

      if (!result.isOk) {
        throw TransientFailureException('Channel page is broken');
      }
      return result;
    });
  }

  ///
  static Future<ChannelPage> getByUsername(
    YoutubeHttpClient httpClient,
    String username,
  ) {
    var url = 'https://www.youtube.com/user/$username?hl=en';

    return retry(httpClient, () async {
      try {
        final raw = await httpClient.getString(url);
        final result = ChannelPage.parse(raw);

        if (!result.isOk) {
          throw TransientFailureException('Channel page is broken');
        }
        return result;
      } on FatalFailureException catch (e) {
        if (e.statusCode != 404) {
          rethrow;
        }
        url = 'https://www.youtube.com/c/$username?hl=en';
      }
      throw FatalFailureException('', 0);
    });
  }

  ///
  static Future<ChannelPage> getByHandle(
    YoutubeHttpClient httpClient,
    String handle,
  ) {
    final url = 'https://www.youtube.com/$handle?hl=en';

    return retry(httpClient, () async {
      try {
        final raw = await httpClient.getString(url);
        final result = ChannelPage.parse(raw);

        if (!result.isOk) {
          throw TransientFailureException('Channel page is broken');
        }
        return result;
      } on FatalFailureException catch (e) {
        if (e.statusCode != 404) {
          rethrow;
        }
      }
      throw FatalFailureException('', 0);
    });
  }

  ///yfq 获取频道内歌单列表数据
  static Future<List<Playlist>> getPlaylists(
      YoutubeHttpClient httpClient, String id) {
    final url = 'https://www.youtube.com/channel/$id/playlists?hl=en';

    return retry(httpClient, () async {
      final raw = await httpClient.getString(url);
      final result = ChannelPage.parse(raw);

      if (!result.isOk) {
        throw TransientFailureException('Channel page is broken');
      }
      return result.playlists;
    });
  }

  ///yfq 获取频道内发布作品列表数据
  static Future<List<Playlist>> getReleaseLists(
      YoutubeHttpClient httpClient, String id) {
    final url = 'https://www.youtube.com/channel/$id/releases?hl=en';

    return retry(httpClient, () async {
      final raw = await httpClient.getString(url);
      final result = ChannelPage.parse(raw);

      if (!result.isOk) {
        throw TransientFailureException('Channel page is broken');
      }
      return result.releaseLists;
    });
  }
}

class _InitialData extends InitialData {
  static final RegExp _subCountExp = RegExp(r'(\d+(?:\.\d+)?)(K|M|\s)');

  _InitialData(super.root);

  int? get subscribersCount {
    final renderer = root.get('header')?.get('c4TabbedHeaderRenderer');
    if (renderer?['subscriberCountText'] == null) {
      return null;
    }
    final subText =
        renderer?.get('subscriberCountText')?.getT<String>('simpleText');
    if (subText == null) {
      return null;
    }
    final match = _subCountExp.firstMatch(subText);
    if (match == null) {
      return null;
    }
    if (match.groupCount != 2) {
      return null;
    }

    final count = double.tryParse(match.group(1) ?? '');
    if (count == null) {
      return null;
    }

    final multiplierText = match.group(2);
    if (multiplierText == null) {
      return null;
    }

    var multiplier = 1;
    if (multiplierText == 'K') {
      multiplier = 1000;
    } else if (multiplierText == 'M') {
      multiplier = 1000000;
    }

    return (count * multiplier).toInt();
  }

  String? get bannerUrl => root
      .get('header')
      ?.get('c4TabbedHeaderRenderer')
      ?.get('banner')
      ?.getList('thumbnails')
      ?.first
      .getT<String>('url');
}
