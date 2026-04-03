import 'package:collection/collection.dart';
import 'package:html/parser.dart' as parser;

import '../../../youtube_explode_dart.dart';
import '../../extensions/helpers_extension.dart';
import '../../retry.dart';
import '../models/initial_data.dart';
import '../models/youtube_page.dart';

/// Reverse engineering page for channel Releases tab with
/// continuation (pagination) support.
class ChannelReleasePage extends YoutubePage<_InitialData> {
  /// The channel ID this page belongs to.
  final String channelId;

  /// Parsed release playlists from this page.
  late final List<Playlist> releases = initialData.releases;

  /// Construct from raw initial data (used for continuation pages).
  ChannelReleasePage.id(this.channelId, super.initialData)
      : super.fromInitialData();

  /// Construct by parsing raw HTML (used for the first page).
  ChannelReleasePage.parse(String raw, this.channelId)
      : super(parser.parse(raw), (root) => _InitialData(root));

  /// Fetches the next page of releases using the continuation
  /// token. Returns `null` when there are no more pages.
  Future<ChannelReleasePage?> nextPage(
    YoutubeHttpClient httpClient,
  ) async {
    if (initialData.token.isEmpty) {
      return null;
    }

    final data = await httpClient.sendContinuation(
      'browse',
      initialData.token,
    );
    return ChannelReleasePage.id(channelId, _InitialData(data));
  }

  /// Fetches the first page of releases for the given channel.
  static Future<ChannelReleasePage> get(
    YoutubeHttpClient httpClient,
    String channelId,
  ) {
    final url = 'https://www.youtube.com/channel/$channelId/releases?hl=en';
    return retry(httpClient, () async {
      final raw = await httpClient.getString(url);
      return ChannelReleasePage.parse(raw, channelId);
    });
  }
}

class _InitialData extends InitialData {
  _InitialData(super.root);

  late final String token = _getContinuationToken();

  late final List<Playlist> releases = _getReleases();

  /// Extracts the content list from either the initial HTML
  /// response or a continuation JSON response.
  List<JsonMap> _getContentContext() {
    List<JsonMap>? context;

    // First page: data comes from the HTML-embedded initial data.
    if (root.containsKey('contents')) {
      context = root
          .get('contents')
          ?.get('twoColumnBrowseResultsRenderer')
          ?.getList('tabs')
          ?.firstWhereOrNull(
            (e) => e['tabRenderer']?['title'] == 'Releases',
          )
          ?.get('tabRenderer')
          ?.get('content')
          ?.get('richGridRenderer')
          ?.getList('contents')
          ?.cast<JsonMap>();
    }

    // Continuation page: data comes from the API response.
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

  /// Extracts the continuation token for the next page.
  String _getContinuationToken() {
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
    return '';
  }

  /// Parses release playlists from the content context.
  List<Playlist> _getReleases() {
    final contents = _getContentContext();
    final List<Playlist> playlists = [];

    for (final item in contents) {
      if (item['richItemRenderer'] == null) {
        continue;
      }

      final Map<String, dynamic>? playlistRenderer =
          item.getJson<Map<String, dynamic>>(
        'richItemRenderer/content/playlistRenderer',
      );
      if (playlistRenderer == null) {
        continue;
      }

      final String? playlistId = playlistRenderer.getT<String>('playlistId');
      final String? title =
          playlistRenderer.getJson<String>('title/simpleText');
      final int videoCount =
          playlistRenderer.getT<String>('videoCount')?.parseInt() ?? 0;
      final String? author =
          playlistRenderer.getJson<String>('shortBylineText/runs/0/text');
      final String? videoId = playlistRenderer
          .getJson<String>('videos/0/childVideoRenderer/videoId');

      final playlistThumbnails = playlistRenderer
          .getJson<List<dynamic>>(
              'thumbnailRenderer/playlistCustomThumbnailRenderer/thumbnail/thumbnails')
          ?.cast<Map<String, dynamic>>()
          .map(
            (e) => Thumbnail(
              Uri.parse(e['url'] as String),
              e['height'] as int,
              e['width'] as int,
            ),
          )
          .toList();

      if (videoId == null ||
          title == null ||
          playlistId == null ||
          videoId.isEmpty ||
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
          ThumbnailSet(videoId),
          Engagement(videoCount, null, null),
          videoCount,
          playlistThumbnails: playlistThumbnails,
        ),
      );
    }

    return playlists;
  }
}
