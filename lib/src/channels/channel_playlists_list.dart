import 'dart:async';

import '../../youtube_explode_dart.dart';
import '../reverse_engineering/pages/channel_playlist_page.dart';

/// A paginated list of channel playlists.
///
/// This behaves like a [List] but has [nextPage] to fetch
/// the next batch of playlists.
class ChannelPlaylistsList extends BasePagedList<Playlist> {
  final ChannelPlaylistPage _page;
  final YoutubeHttpClient _httpClient;

  /// The channel ID these playlists belong to.
  final ChannelId channelId;

  /// Construct an instance of [ChannelPlaylistsList].
  ChannelPlaylistsList(
    super.base,
    this.channelId,
    this._page,
    this._httpClient,
  );

  /// Fetches the next batch of playlists or returns `null` if
  /// there are no more results.
  @override
  Future<ChannelPlaylistsList?> nextPage() async {
    final page = await _page.nextPage(_httpClient);
    if (page == null) {
      return null;
    }
    return ChannelPlaylistsList(
      page.playlists,
      channelId,
      page,
      _httpClient,
    );
  }
}
