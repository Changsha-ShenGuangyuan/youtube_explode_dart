import 'dart:async';

import '../../youtube_explode_dart.dart';
import '../reverse_engineering/pages/channel_release_page.dart';

/// A paginated list of channel release playlists.
///
/// This behaves like a [List] but has [nextPage] to fetch
/// the next batch of releases.
class ChannelReleasesList extends BasePagedList<Playlist> {
  final ChannelReleasePage _page;
  final YoutubeHttpClient _httpClient;

  /// The channel ID these releases belong to.
  final ChannelId channelId;

  /// Construct an instance of [ChannelReleasesList].
  ChannelReleasesList(
    super.base,
    this.channelId,
    this._page,
    this._httpClient,
  );

  /// Fetches the next batch of releases or returns `null` if
  /// there are no more results.
  @override
  Future<ChannelReleasesList?> nextPage() async {
    final page = await _page.nextPage(_httpClient);
    if (page == null) {
      return null;
    }
    return ChannelReleasesList(
      page.releases,
      channelId,
      page,
      _httpClient,
    );
  }
}
