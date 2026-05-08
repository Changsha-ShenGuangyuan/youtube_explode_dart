import 'package:collection/collection.dart';
import 'package:html/parser.dart' as parser;

import '../../channels/channel_video.dart';
import '../../channels/video_type.dart';
import '../../exceptions/exceptions.dart';
import '../../extensions/helpers_extension.dart';
import '../../retry.dart';
import '../../videos/videos.dart';
import '../models/initial_data.dart';
import '../models/youtube_page.dart';
import '../youtube_http_client.dart';

///
class ChannelUploadPage extends YoutubePage<_InitialData> {
  ///
  final String channelId;

  final VideoType type;

  late final List<ChannelVideo> uploads = initialData.uploads;

  /// InitialData
  ChannelUploadPage.id(this.channelId, this.type, super.initialData)
      : super.fromInitialData();

  ///
  Future<ChannelUploadPage?> nextPage(YoutubeHttpClient httpClient) async {
    if (initialData.token.isEmpty) {
      return null;
    }

    final data = await httpClient.sendContinuation('browse', initialData.token);
    return ChannelUploadPage.id(channelId, type, _InitialData(data, type));
  }

  ///
  static Future<ChannelUploadPage> get(
    YoutubeHttpClient httpClient,
    String channelId,
    String sorting,
    VideoType type,
  ) {
    final url =
        'https://www.youtube.com/channel/$channelId/${type.name}?view=0&sort=$sorting&flow=grid';
    return retry(httpClient, () async {
      final raw = await httpClient.getString(url);
      return ChannelUploadPage.parse(raw, channelId, type);
    });
  }

  ///
  ChannelUploadPage.parse(String raw, this.channelId, this.type)
      : super(parser.parse(raw), (root) => _InitialData(root, type));
}

class _InitialData extends InitialData {
  _InitialData(super.root, this.type);

  final VideoType type;

  late final JsonMap? continuationContext = getContinuationContext();

  late final String token = continuationContext?.getT<String>('token') ??
      continuationContext?.getT<String>('continuation') ??
      '';

  late final List<ChannelVideo> uploads = _getUploads();

  List<ChannelVideo> _getUploads() {
    final content = getContentContext();
    if (content.isEmpty) {
      return const <ChannelVideo>[];
    }
    return content.map(_parseContent).nonNulls.toList();
  }

  List<JsonMap> getContentContext() {
    List<JsonMap>? context;
    if (root.containsKey('contents')) {
      var render = root
          .get('contents')
          ?.get('twoColumnBrowseResultsRenderer')
          ?.getList('tabs')
          ?.map((e) => e['tabRenderer'])
          .cast<JsonMap>()
          .firstWhereOrNull((e) => e['selected'] as bool? ?? false)
          ?.get('content');

      if (render != null) {
        if (render.containsKey('sectionListRenderer')) {
          render = render
              .get('sectionListRenderer')
              ?.getList('contents')
              ?.firstOrNull
              ?.get('itemSectionRenderer')
              ?.getList('contents')
              ?.firstOrNull;

          if (render?.containsKey('gridRenderer') ?? false) {
            context =
                render?.get('gridRenderer')?.getList('items')?.cast<JsonMap>();
          } else if (render?.containsKey('messageRenderer') ?? false) {
            // Workaround for no-videos.
            context = const [];
          }
        } else if (render.containsKey('richGridRenderer')) {
          context =
              render.get('richGridRenderer')?.getList('contents') ?? const [];
        }
      }

      // Fallback: Topic/Artist channels use lockupViewModel
      // inside shelfRenderer on the Home tab.
      if (context == null || context.isEmpty) {
        context = _getTopicVideoLockups();
      }
    }
    if (context == null && root.containsKey('onResponseReceivedActions')) {
      context = root
          .getList('onResponseReceivedActions')
          ?.firstOrNull
          ?.get('appendContinuationItemsAction')
          ?.getList('continuationItems')
          ?.cast<JsonMap>();
    }
    if (context == null) {
      throw FatalFailureException('Failed to get initial data context.', 0);
    }
    return context;
  }

  //yfq---
  /// Extracts lockupViewModel video items from Topic/Artist
  /// channel's Home tab shelfRenderer sections.
  ///
  /// Topic channels (e.g. music artist channels) don't have
  /// a dedicated Videos tab with data pre-loaded. Instead, the
  /// Home tab contains shelfRenderers with horizontalListRenderer
  /// items using lockupViewModel with contentType
  /// LOCKUP_CONTENT_TYPE_VIDEO.
  List<JsonMap> _getTopicVideoLockups() {
    if (!root.containsKey('contents')) {
      return const [];
    }

    final tabs = root
        .get('contents')
        ?.get('twoColumnBrowseResultsRenderer')
        ?.getList('tabs');
    if (tabs == null) return const [];

    // Collect all lockupViewModel video items from all
    // shelfRenderer sections.
    final List<JsonMap> result = [];

    for (final tab in tabs) {
      final tr = tab.get('tabRenderer');
      if (tr == null) continue;
      // Only process the selected tab (typically Home).
      if (!(tr.getT<bool>('selected') ?? false)) continue;

      final sections =
          tr.get('content')?.get('sectionListRenderer')?.getList('contents');
      if (sections == null) continue;

      for (final section in sections) {
        final isr = section.get('itemSectionRenderer')?.getList('contents');
        if (isr == null) continue;

        for (final content in isr) {
          if (!content.containsKey('shelfRenderer')) continue;

          final items = content
              .get('shelfRenderer')
              ?.get('content')
              ?.get('horizontalListRenderer')
              ?.getList('items');
          if (items == null || items.isEmpty) continue;

          // Check if items are videos (not stations, albums, etc.)
          final firstType =
              items.first.get('lockupViewModel')?.getT<String>('contentType');
          if (firstType != 'LOCKUP_CONTENT_TYPE_VIDEO') continue;

          for (final item in items) {
            if (item.containsKey('lockupViewModel')) {
              result.add(item);
            }
          }
        }
      }
    }

    return result;
  }

//---yfq--end
  JsonMap? getContinuationContext() {
    // Avoid re-entering _getTopicVideoLockups when content
    // came from the topic fallback (no continuation for topic
    // video shelves).
    List<JsonMap>? stdContext;
    try {
      stdContext = _getStandardContentContext();
    } catch (_) {
      // Standard context not available — will use topic fallback
      // which has no continuation support.
    }

    if (stdContext != null && stdContext.isNotEmpty) {
      final continuationItemRenderer = stdContext
          .firstWhereOrNull((e) => e['continuationItemRenderer'] != null)
          ?.get('continuationItemRenderer');
      if (continuationItemRenderer != null) {
        final command = continuationItemRenderer
            .get('continuationEndpoint')
            ?.get('continuationCommand');
        if (command != null) {
          return command;
        }
      }
    }

    if (root.containsKey('contents')) {
      return root
          .get('contents')
          ?.get('twoColumnBrowseResultsRenderer')
          ?.getList('tabs')
          ?.map((e) => e['tabRenderer'])
          .cast<JsonMap>()
          .firstWhereOrNull((e) => e['selected'] as bool? ?? false)
          ?.get('content')
          ?.get('sectionListRenderer')
          ?.getList('contents')
          ?.firstOrNull
          ?.get('itemSectionRenderer')
          ?.getList('contents')
          ?.firstOrNull
          ?.get('gridRenderer')
          ?.getList('items')
          ?.firstWhereOrNull((e) => e['continuationItemRenderer'] != null)
          ?.get('continuationItemRenderer')
          ?.get('continuationEndpoint')
          ?.get('continuationCommand');
    }
    if (root.containsKey('onResponseReceivedActions')) {
      return root
          .getList('onResponseReceivedActions')
          ?.firstOrNull
          ?.get('appendContinuationItemsAction')
          ?.getList('continuationItems')
          ?.firstWhereOrNull((e) => e['continuationItemRenderer'] != null)
          ?.get('continuationItemRenderer')
          ?.get('continuationEndpoint')
          ?.get('continuationCommand');
    }
    return null;
  }

  //---yfq
  /// Gets standard content context without topic fallback
  /// to avoid infinite recursion between
  /// getContentContext <-> getContinuationContext.
  List<JsonMap>? _getStandardContentContext() {
    if (root.containsKey('contents')) {
      var render = root
          .get('contents')
          ?.get('twoColumnBrowseResultsRenderer')
          ?.getList('tabs')
          ?.map((e) => e['tabRenderer'])
          .cast<JsonMap>()
          .firstWhereOrNull((e) => e['selected'] as bool? ?? false)
          ?.get('content');

      if (render != null) {
        if (render.containsKey('sectionListRenderer')) {
          render = render
              .get('sectionListRenderer')
              ?.getList('contents')
              ?.firstOrNull
              ?.get('itemSectionRenderer')
              ?.getList('contents')
              ?.firstOrNull;

          if (render?.containsKey('gridRenderer') ?? false) {
            return render
                ?.get('gridRenderer')
                ?.getList('items')
                ?.cast<JsonMap>();
          }
        } else if (render.containsKey('richGridRenderer')) {
          return render
              .get('richGridRenderer')
              ?.getList('contents')
              ?.cast<JsonMap>();
        }
      }
    }
    if (root.containsKey('onResponseReceivedActions')) {
      return root
          .getList('onResponseReceivedActions')
          ?.firstOrNull
          ?.get('appendContinuationItemsAction')
          ?.getList('continuationItems')
          ?.cast<JsonMap>();
    }
    return null;
  }

//---yfq
  ChannelVideo? _parseContent(JsonMap? content) {
    if (content == null) {
      return null;
    }

    Map<String, dynamic>? video;
    if (content.containsKey('gridVideoRenderer')) {
      video = content.get('gridVideoRenderer');
    } else if (content.containsKey('richItemRenderer')) {
      final richContent = content.get('richItemRenderer')?.get('content');
      video = richContent?.get(type.youtubeRenderText);
      if (type == VideoType.shorts && video != null) {
        return ChannelVideo(
            VideoId(video.getJson<String>(
                'onTap/innertubeCommand/reelWatchEndpoint/videoId')!),
            video.getJson<String>('overlayMetadata/primaryText/content')!,
            Duration.zero,
            video.getJson<String>('thumbnail/sources/0/url')!,
            '',
            video
                .getJson<String>('overlayMetadata/secondaryText/content')!
                .parseInt()!);
      }
      //---yfq
      // Fallback: new YouTube format uses lockupViewModel
      // inside richItemRenderer.content instead of
      // videoRenderer.
      if (video == null && richContent != null) {
        final lockup = richContent.get('lockupViewModel');
        if (lockup != null) {
          return _parseLockupViewModel(lockup);
        }
      }
    } else if (content.containsKey('lockupViewModel')) {
      // New format used by Topic/Artist channels.
      return _parseLockupViewModel(content.get('lockupViewModel')!);
      //---yfq--end
    }

    if (video == null) {
      return null;
    }
    return ChannelVideo(
      VideoId(video.getT<String>('videoId')!),
      video.get('title')?.getT<String>('simpleText') ??
          video.get('title')?.getList('runs')?.map((e) => e['text']).join() ??
          '',
      video
              .getList('thumbnailOverlays')
              ?.firstOrNull
              ?.get('thumbnailOverlayTimeStatusRenderer')
              ?.get('text')
              ?.getT<String>('simpleText')
              ?.toDuration() ??
          Duration.zero,
      video.get('thumbnail')?.getList('thumbnails')?.last.getT<String>('url') ??
          '',
      video.get('publishedTimeText')?.getT<String>('simpleText') ?? '',
      video.get('viewCountText')?.getT<String>('simpleText').parseInt() ?? 0,
    );
  }

  //yfq
  /// Parses a lockupViewModel item with
  /// contentType == LOCKUP_CONTENT_TYPE_VIDEO into
  /// a [ChannelVideo].
  ///
  /// Structure:
  /// - contentId → videoId
  /// - metadata.lockupMetadataViewModel.title.content → title
  /// - contentImage.thumbnailViewModel.overlays[0]
  ///     .thumbnailBottomOverlayViewModel.badges[0]
  ///     .thumbnailBadgeViewModel.text → duration (e.g. "4:27")
  /// - contentImage.thumbnailViewModel.image.sources → thumbnails
  /// - metadata.lockupMetadataViewModel.metadata
  ///     .contentMetadataViewModel.metadataRows → views, upload date
  ChannelVideo? _parseLockupViewModel(JsonMap viewModel) {
    final contentType = viewModel.getT<String>('contentType');
    if (contentType != 'LOCKUP_CONTENT_TYPE_VIDEO') {
      return null;
    }

    final String? videoId = viewModel.getT<String>('contentId');
    if (videoId == null || videoId.isEmpty) {
      return null;
    }

    // Title
    final String title = viewModel.getJson<String>(
            'metadata/lockupMetadataViewModel/title/content') ??
        '';

    // Duration from thumbnail badge
    final String durationText =
        viewModel.getJson<String>('contentImage/thumbnailViewModel/overlays/0/'
                'thumbnailBottomOverlayViewModel/badges/0/'
                'thumbnailBadgeViewModel/text') ??
            '';

    // Thumbnail URL: last source for highest resolution
    final thumbnailSources = viewModel.getJson<List<dynamic>>(
        'contentImage/thumbnailViewModel/image/sources');
    final String thumbnailUrl = (thumbnailSources != null &&
            thumbnailSources.isNotEmpty)
        ? (thumbnailSources.last as Map<String, dynamic>)['url'] as String? ??
            ''
        : '';

    // Metadata rows contain artist, view count, upload date
    final metadataRows = viewModel
        .getJson<List<dynamic>>('metadata/lockupMetadataViewModel/metadata/'
            'contentMetadataViewModel/metadataRows');

    String uploadDate = '';
    int viewCount = 0;

    if (metadataRows != null) {
      for (final row in metadataRows) {
        final parts =
            (row as Map<String, dynamic>)['metadataParts'] as List<dynamic>?;
        if (parts == null) continue;
        for (final part in parts) {
          final text =
              (part as Map<String, dynamic>).getJson<String>('text/content') ??
                  '';
          if (text.isEmpty) continue;

          // Detect upload date first (e.g. "13 days ago",
          // "2 months ago").
          if (text.contains('ago')) {
            uploadDate = text;
            continue;
          }

          // Detect view count: handles both formats:
          // - "6.3M views" (live response)
          // - "6.3M" (compact format)
          if (text.contains('view')) {
            // Format: "6.3M views" or "5 views"
            viewCount = text.parseViewCount() ?? 0;
          } else if (!text.contains(' ')) {
            // Compact format: "6.3M", "1.5K", "500"
            final parsed = text.parseIntWithUnits();
            if (parsed != null && parsed > 0) {
              viewCount = parsed;
            }
          }
        }
      }
    }

    return ChannelVideo(
      VideoId(videoId),
      title,
      durationText.toDuration() ?? Duration.zero,
      thumbnailUrl,
      uploadDate,
      viewCount,
    );
  }
}

//
