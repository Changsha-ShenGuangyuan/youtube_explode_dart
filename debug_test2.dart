// Debug: check richItemRenderer content structure
import 'dart:convert';
import 'package:youtube_explode_dart/src/reverse_engineering/youtube_http_client.dart';

void main() async {
  final httpClient = YoutubeHttpClient();

  final url =
      'https://www.youtube.com/channel/UC5OrDvL9DscpcAstz7JnQGA/videos?view=0&sort=dd&flow=grid';

  final raw = await httpClient.getString(url);

  final startMarker = 'var ytInitialData = ';
  final start = raw.indexOf(startMarker) + startMarker.length;
  var braceCount = 0;
  var endIdx = start;
  for (var i = start; i < raw.length; i++) {
    if (raw[i] == '{') braceCount++;
    if (raw[i] == '}') {
      braceCount--;
      if (braceCount == 0) {
        endIdx = i + 1;
        break;
      }
    }
  }

  final data = json.decode(raw.substring(start, endIdx)) as Map<String, dynamic>;

  final tabs = data['contents']['twoColumnBrowseResultsRenderer']['tabs'] as List;
  for (final tab in tabs) {
    final tr = tab['tabRenderer'] as Map<String, dynamic>?;
    if (tr == null) continue;
    if (tr['selected'] != true) continue;

    final rg = tr['content']['richGridRenderer'] as Map<String, dynamic>;
    final items = rg['contents'] as List;

    for (var i = 0; i < items.length && i < 3; i++) {
      final item = items[i] as Map<String, dynamic>;
      if (item.containsKey('richItemRenderer')) {
        final rir = item['richItemRenderer'] as Map<String, dynamic>;
        final content = rir['content'] as Map<String, dynamic>;
        print('richItemRenderer[$i] content keys: ${content.keys.toList()}');

        if (content.containsKey('videoRenderer')) {
          final vr = content['videoRenderer'] as Map<String, dynamic>;
          print('  videoRenderer videoId: ${vr['videoId']}');
          final title = vr['title'];
          if (title is Map) {
            final runs = title['runs'] as List?;
            if (runs != null && runs.isNotEmpty) {
              print('  title: ${runs[0]['text']}');
            }
          }
        } else if (content.containsKey('lockupViewModel')) {
          final lvm = content['lockupViewModel'] as Map<String, dynamic>;
          print('  lockupViewModel contentType: ${lvm['contentType']}');
          print('  lockupViewModel contentId: ${lvm['contentId']}');
          final meta = lvm['metadata'] as Map<String, dynamic>?;
          final lmvm = meta?['lockupMetadataViewModel'] as Map<String, dynamic>?;
          final title = lmvm?['title'] as Map<String, dynamic>?;
          print('  title: ${title?['content']}');
        } else {
          print('  Unknown content: ${content.keys.toList()}');
          print('  ${json.encode(content).substring(0, 500)}');
        }
      } else if (item.containsKey('continuationItemRenderer')) {
        print('item[$i]: continuationItemRenderer');
      } else {
        print('item[$i] keys: ${item.keys.toList()}');
      }
    }
    break;
  }

  httpClient.close();
}
