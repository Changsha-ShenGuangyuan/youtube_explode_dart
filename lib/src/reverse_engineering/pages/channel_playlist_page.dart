import 'package:collection/collection.dart';
import 'package:html/parser.dart' as parser;

import '../../../youtube_explode_dart.dart';
import '../../extensions/helpers_extension.dart';
import '../../retry.dart';
import '../models/initial_data.dart';
import '../models/youtube_page.dart';

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
    final url =
        'https://www.youtube.com/channel/$channelId/playlists?hl=en';
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

    // First page: gridRenderer path.
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
    if (context == null &&
        root.containsKey('onResponseReceivedActions')) {
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

  /// Parses playlists from lockupViewModel items.
  List<Playlist> _getPlaylists() {
    final contents = _getContentContext();
    final List<Playlist> playlists = [];

    for (final item in contents) {
      if (item['lockupViewModel'] == null) {
        continue;
      }

      final viewModel = item.get('lockupViewModel')!;

      final type = viewModel.getT<String>('contentType');
      if (type != 'LOCKUP_CONTENT_TYPE_PLAYLIST') {
        continue;
      }

      final String? playlistId =
          viewModel.getT<String>('contentId');
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
          '',
          '',
          ThumbnailSet(videoId),
          Engagement(videoCount, null, null),
          videoCount,
        ),
      );
    }

    return playlists;
  }
}
