import 'package:collection/collection.dart';
import 'package:html/parser.dart' as parser;

import '../../../youtube_explode_dart.dart';
import '../../extensions/helpers_extension.dart';
import '../../retry.dart';
import '../models/initial_data.dart';
import '../models/youtube_page.dart';

//yfq 新增的歌单专辑
/// Reverse engineering page for channel Playlists tab with
/// continuation (pagination) support.
class ChannelPlaylistPage extends YoutubePage<_InitialData> {
  /// The channel ID this page belongs to.
  final String channelId;

  /// Parsed playlists from this page.
  late final List<Playlist> playlists = initialData.playlists;

  /// Construct from raw initial data (used for continuation pages).
  ChannelPlaylistPage.id(this.channelId, super.initialData)
      : super.fromInitialData();

  /// Construct by parsing raw HTML (used for the first page).
  ChannelPlaylistPage.parse(String raw, this.channelId)
      : super(parser.parse(raw), (root) => _InitialData(root));

  /// Fetches the next page of playlists using the continuation
  /// token. Returns `null` when there are no more pages.
  Future<ChannelPlaylistPage?> nextPage(
    YoutubeHttpClient httpClient,
  ) async {
    if (initialData.token.isEmpty) {
      return null;
    }

    final data = await httpClient.sendContinuation(
      'browse',
      initialData.token,
    );
    return ChannelPlaylistPage.id(channelId, _InitialData(data));
  }

  /// Fetches the first page of playlists for the given channel.
  static Future<ChannelPlaylistPage> get(
    YoutubeHttpClient httpClient,
    String channelId,
  ) {
    final url = 'https://www.youtube.com/channel/$channelId/playlists?hl=en';
    return retry(httpClient, () async {
      final raw = await httpClient.getString(url);
      return ChannelPlaylistPage.parse(raw, channelId);
    });
  }
}

class _InitialData extends InitialData {
  _InitialData(super.root);

  late final String token = _getContinuationToken();

  late final List<Playlist> playlists = _getPlaylists();

  /// Extracts the content list from either the initial HTML
  /// response or a continuation JSON response.
  List<JsonMap> _getContentContext() {
    List<JsonMap>? context;

    // First page: gridRenderer path (standard Playlists tab).
    if (root.containsKey('contents')) {
      context = root
          .get('contents')
          ?.get('twoColumnBrowseResultsRenderer')
          ?.getList('tabs')
          ?.firstWhereOrNull(
            (e) => e['tabRenderer']?['title'] == 'Playlists',
          )
          ?.get('tabRenderer')
          ?.get('content')
          ?.get('sectionListRenderer')
          ?.getList('contents')
          ?.firstOrNull
          ?.get('itemSectionRenderer')
          ?.getList('contents')
          ?.firstOrNull
          ?.get('gridRenderer')
          ?.getList('items')
          ?.cast<JsonMap>();
    }

    // Continuation page: data from API response.
    if (context == null && root.containsKey('onResponseReceivedActions')) {
      context = root
          .getList('onResponseReceivedActions')
          ?.firstOrNull
          ?.get('appendContinuationItemsAction')
          ?.getList('continuationItems')
          ?.cast<JsonMap>();
    }

    return context ?? const [];
  }

  /// Extracts lockupViewModel items from Topic channel's Home tab
  /// shelfRenderer (Albums & Singles section).
  List<JsonMap> _getTopicPlaylistLockups() {
    if (!root.containsKey('contents') &&
        !root.containsKey('onResponseReceivedEndpoints')) {
      return const [];
    }

    //分页加载的时候返回的结果不一样
    if (root.containsKey('onResponseReceivedEndpoints')) {
      final items = root
          .getList('onResponseReceivedEndpoints')
          ?.firstOrNull
          ?.get('appendContinuationItemsAction')
          ?.getList('continuationItems')
          ?.firstOrNull
          ?.get('gridRenderer')
          ?.getList('items');
      // if (items == null) return const [];

      final items2 = root
          .getList('onResponseReceivedEndpoints')
          ?.firstOrNull
          ?.get('appendContinuationItemsAction')
          ?.getList('continuationItems');
      if (items == null && items2 == null) return const [];

      List<JsonMap> list = [];
      if (items != null) {
        for (final item in items) {
          final sections = item.get('gridPlaylistRenderer');
          if (sections != null) {
            list.add(sections);
          }
        }
      }
      if (items2 != null) {
        for (final item in items2) {
          final sections = item.get('gridPlaylistRenderer');
          if (sections != null) {
            list.add(sections);
          }
        }
      }

      return list;
    }

    final tabs = root
        .get('contents')
        ?.get('twoColumnBrowseResultsRenderer')
        ?.getList('tabs');
    if (tabs == null) return const [];

    for (final tab in tabs) {
      final sections = tab
          .get('tabRenderer')
          ?.get('content')
          ?.get('sectionListRenderer')
          ?.getList('contents');
      if (sections == null) continue;

      for (final section in sections) {
        final shelf = section.get('itemSectionRenderer')?.getList('contents');
        if (shelf == null) continue;

        for (final shelfItem in shelf) {
          final items = shelfItem
              .get('shelfRenderer')
              ?.get('content')
              ?.get('horizontalListRenderer')
              ?.getList('items');
          if (items == null || items.isEmpty) continue;

          final firstType =
              items.first.get('lockupViewModel')?.getT<String>('contentType');
          if (firstType == 'LOCKUP_CONTENT_TYPE_ALBUM') {
            return items.cast<JsonMap>();
          }
        }
      }
    }
    return const [];
  }

  /// Extracts the continuation token for the next page.
  String _getContinuationToken() {
    // 1. Standard: from gridRenderer continuation items
    final items = _getContentContext();
    final continuationItem = items
        .firstWhereOrNull(
          (e) => e['continuationItemRenderer'] != null,
        )
        ?.get('continuationItemRenderer');

    if (continuationItem != null) {
      return continuationItem
              .get('continuationEndpoint')
              ?.get('continuationCommand')
              ?.getT<String>('token') ??
          continuationItem
              .get('continuationEndpoint')
              ?.get('continuationCommand')
              ?.getT<String>('continuation') ??
          '';
    }

    // 2. Topic continuation: gridRenderer inside
    //    onResponseReceivedEndpoints
    if (root.containsKey('onResponseReceivedEndpoints')) {
      final gridItems = root
          .getList('onResponseReceivedEndpoints')
          ?.firstOrNull
          ?.get('appendContinuationItemsAction')
          ?.getList('continuationItems');
      // ?.firstOrNull
      // ?.get('gridRenderer')
      // ?.getList('items');
      if (gridItems != null) {
        final gridCont = gridItems
            .firstWhereOrNull(
              (e) => e['continuationItemRenderer'] != null,
            )
            ?.get('continuationItemRenderer');
        if (gridCont != null) {
          return gridCont
                  .get('continuationEndpoint')
                  ?.get('continuationCommand')
                  ?.getT<String>('token') ??
              gridCont
                  .get('continuationEndpoint')
                  ?.get('continuationCommand')
                  ?.getT<String>('continuation') ??
              '';
        } else {
          final gridItems2 =
              gridItems.firstOrNull?.get('gridRenderer')?.getList('items');

          final gridCont = gridItems2
              ?.firstWhereOrNull(
                (e) => e['continuationItemRenderer'] != null,
              )
              ?.get('continuationItemRenderer');
          if (gridCont != null) {
            return gridCont
                    .get('continuationEndpoint')
                    ?.get('continuationCommand')
                    ?.getT<String>('token') ??
                gridCont
                    .get('continuationEndpoint')
                    ?.get('continuationCommand')
                    ?.getT<String>('continuation') ??
                '';
          }
        }
      }
    }

    // 3. Topic channel first page: from engagement panel's
    //    "View all" button
    return _getTopicContinuationToken();
  }

  /// Extracts continuation token from Topic channel's
  /// "View all" engagement panel in the Albums & Singles shelf.
  String _getTopicContinuationToken() {
    if (!root.containsKey('contents')) return '';

    final tabs = root
        .get('contents')
        ?.get('twoColumnBrowseResultsRenderer')
        ?.getList('tabs');
    if (tabs == null) return '';

    for (final tab in tabs) {
      final sections = tab
          .get('tabRenderer')
          ?.get('content')
          ?.get('sectionListRenderer')
          ?.getList('contents');
      if (sections == null) continue;

      for (final section in sections) {
        final shelf = section.get('itemSectionRenderer')?.getList('contents');
        if (shelf == null) continue;

        for (final shelfItem in shelf) {
          final sr = shelfItem.get('shelfRenderer');
          if (sr == null) continue;

          // Verify this is the Albums shelf
          final items = sr
              .get('content')
              ?.get('horizontalListRenderer')
              ?.getList('items');
          if (items == null || items.isEmpty) continue;

          final firstType =
              items.first.get('lockupViewModel')?.getT<String>('contentType');
          if (firstType != 'LOCKUP_CONTENT_TYPE_ALBUM') continue;

          // Found the albums shelf — extract token from
          // "View all" button's engagement panel
          final topLevelButtons =
              sr.get('menu')?.get('menuRenderer')?.getList('topLevelButtons');
          if (topLevelButtons == null) continue;

          for (final btn in topLevelButtons) {
            final panel = btn
                .get('buttonRenderer')
                ?.get('navigationEndpoint')
                ?.get('showEngagementPanelEndpoint')
                ?.get('engagementPanel')
                ?.get('engagementPanelSectionListRenderer');
            if (panel == null) continue;

            final token = panel
                .get('content')
                ?.get('sectionListRenderer')
                ?.getList('contents')
                ?.firstOrNull
                ?.get('itemSectionRenderer')
                ?.getList('contents')
                ?.firstOrNull
                ?.get('continuationItemRenderer')
                ?.get('continuationEndpoint')
                ?.get('continuationCommand')
                ?.getT<String>('token');
            if (token != null && token.isNotEmpty) return token;
          }
        }
      }
    }
    return '';
  }

  /// Parses playlists from the content context.
  List<Playlist> _getPlaylists() {
    // 1. Try standard Playlists tab format
    final contents = _getContentContext();
    if (contents.isNotEmpty) {
      final parsed = _parseFromLockupViewModel(
        contents,
        'LOCKUP_CONTENT_TYPE_PLAYLIST',
      );
      if (parsed.isNotEmpty) return parsed;

      // Continuation response may contain ALBUM type items
      final albumParsed = _parseFromLockupViewModel(
        contents,
        'LOCKUP_CONTENT_TYPE_ALBUM',
      );
      if (albumParsed.isNotEmpty) return albumParsed;
    }

    // 2. Fallback: Topic channel — lockupViewModel or
    //    gridPlaylistRenderer
    final topicItems = _getTopicPlaylistLockups();
    if (topicItems.isNotEmpty) {
      // Check if items are gridPlaylistRenderer (pagination)
      // or lockupViewModel (first page)
      if (topicItems.first.containsKey('playlistId')) {
        return _parseFromGridPlaylistRenderer(topicItems);
      }
      return _parseFromLockupViewModel(
        topicItems,
        'LOCKUP_CONTENT_TYPE_ALBUM',
      );
    }

    return [];
  }

  /// Parses playlists from lockupViewModel items with the
  /// specified [contentType].
  List<Playlist> _parseFromLockupViewModel(
    List<JsonMap> items,
    String contentType,
  ) {
    final List<Playlist> playlists = [];

    for (final item in items) {
      final viewModel = item.get('lockupViewModel');
      if (viewModel == null) continue;

      final type = viewModel.getT<String>('contentType');
      if (type != contentType) continue;

      final String? playlistId = viewModel.getT<String>('contentId');
      final String? title = viewModel.getJson<String>(
        'metadata/lockupMetadataViewModel/title/content',
      );

      final int videoCount = viewModel
              .getJson<String>(
                'contentImage/collectionThumbnailViewModel/'
                'primaryThumbnail/thumbnailViewModel/overlays/0/'
                'thumbnailOverlayBadgeViewModel/thumbnailBadges/0/'
                'thumbnailBadgeViewModel/text',
              )
              ?.parseInt() ??
          0;

      final String? videoId = viewModel.getJson<String>(
        'rendererContext/commandContext/onTap/'
        'innertubeCommand/watchEndpoint/videoId',
      );

      // Extract artist name
      final String? author = viewModel.getJson<String>(
        'metadata/lockupMetadataViewModel/metadata/'
        'contentMetadataViewModel/metadataRows/0/'
        'metadataParts/0/text/content',
      );

      final playlistThumbnails = viewModel
          .getJson<List<dynamic>>(
            'contentImage/collectionThumbnailViewModel/'
            'primaryThumbnail/thumbnailViewModel/image/sources',
          )
          ?.cast<Map<String, dynamic>>()
          .map(
            (e) => Thumbnail(
              Uri.parse(e['url'] as String),
              e['height'] as int,
              e['width'] as int,
            ),
          )
          .toList();

      if (title == null ||
          playlistId == null ||
          title.isEmpty ||
          playlistId.isEmpty) {
        continue;
      }

      playlists.add(
        Playlist(
          PlaylistId(playlistId),
          title,
          author ?? '',
          '',
          ThumbnailSet(videoId ?? ''),
          Engagement(videoCount, null, null),
          videoCount,
          playlistThumbnails: playlistThumbnails,
        ),
      );
    }

    return playlists;
  }

  /// Parses playlists from gridPlaylistRenderer items
  /// (Topic channel pagination response format).
  List<Playlist> _parseFromGridPlaylistRenderer(
    List<JsonMap> items,
  ) {
    final List<Playlist> playlists = [];

    for (final renderer in items) {
      final String? playlistId = renderer.getT<String>('playlistId');

      final String? title = renderer
          .get('title')
          ?.getList('runs')
          ?.firstOrNull
          ?.getT<String>('text');

      // Extract video count from "N videos" text
      final int videoCount = renderer
              .get('videoCountText')
              ?.getList('runs')
              ?.firstOrNull
              ?.getT<String>('text')
              ?.parseInt() ??
          0;

      // Extract videoId from navigation endpoint
      final String? videoId = renderer
          .get('navigationEndpoint')
          ?.get('watchEndpoint')
          ?.getT<String>('videoId');

      // Extract author from shortBylineText
      final String? author = renderer
          .get('shortBylineText')
          ?.getList('runs')
          ?.firstOrNull
          ?.getT<String>('text');

      // Extract custom thumbnails from
      // thumbnailRenderer
      final playlistThumbnails = renderer
          .get('thumbnailRenderer')
          ?.get('playlistCustomThumbnailRenderer')
          ?.get('thumbnail')
          ?.getList('thumbnails')
          ?.cast<Map<String, dynamic>>()
          .map(
            (e) => Thumbnail(
              Uri.parse(e['url'] as String),
              (e['height'] as int?) ?? 0,
              (e['width'] as int?) ?? 0,
            ),
          )
          .toList();

      if (title == null ||
          playlistId == null ||
          title.isEmpty ||
          playlistId.isEmpty) {
        continue;
      }

      playlists.add(
        Playlist(
          PlaylistId(playlistId),
          title,
          author ?? '',
          '',
          ThumbnailSet(videoId ?? ''),
          Engagement(videoCount, null, null),
          videoCount,
          playlistThumbnails: playlistThumbnails,
        ),
      );
    }

    return playlists;
  }
}
