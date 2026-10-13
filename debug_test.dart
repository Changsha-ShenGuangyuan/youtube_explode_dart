// Debug test to understand the actual response structure
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/src/reverse_engineering/youtube_http_client.dart';

void main() async {
  final httpClient = YoutubeHttpClient();

  final url =
      'https://www.youtube.com/channel/UC5OrDvL9DscpcAstz7JnQGA/videos?view=0&sort=dd&flow=grid';

  print('Fetching $url ...');
  final raw = await httpClient.getString(url);

  // Extract ytInitialData
  final idx1 = raw.indexOf('var ytInitialData = ');
  if (idx1 == -1) {
    print('ytInitialData not found!');
    // Try the other pattern
    final idx2 = raw.indexOf('window["ytInitialData"] =');
    if (idx2 == -1) {
      print('Neither pattern found. Saving raw to debug.html');
      File('debug_response.html').writeAsStringSync(raw);
      return;
    }
  }

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

  final jsonStr = raw.substring(start, endIdx);
  final data = json.decode(jsonStr) as Map<String, dynamic>;

  // Check tabs
  final tabs = (data['contents'] as Map<String, dynamic>?)?['twoColumnBrowseResultsRenderer']?['tabs'] as List<dynamic>?;
  if (tabs == null) {
    print('No tabs found!');
    return;
  }

  for (var i = 0; i < tabs.length; i++) {
    final tab = tabs[i] as Map<String, dynamic>;
    final tr = tab['tabRenderer'] as Map<String, dynamic>? ??
        tab['expandableTabRenderer'] as Map<String, dynamic>? ??
        {};
    final title = tr['title'] ?? 'N/A';
    final selected = tr['selected'] ?? false;
    final hasContent = tr.containsKey('content');
    print('Tab $i: title=$title, selected=$selected, has_content=$hasContent');

    if (selected && hasContent) {
      final content = tr['content'] as Map<String, dynamic>;
      print('  Content keys: ${content.keys.toList()}');

      if (content.containsKey('richGridRenderer')) {
        final rg = content['richGridRenderer'] as Map<String, dynamic>;
        final items = rg['contents'] as List<dynamic>? ?? [];
        print('  richGridRenderer items: ${items.length}');
        if (items.isNotEmpty) {
          print('  First item keys: ${(items[0] as Map<String, dynamic>).keys.toList()}');
        }
      } else if (content.containsKey('sectionListRenderer')) {
        final sl = content['sectionListRenderer'] as Map<String, dynamic>;
        final sections = sl['contents'] as List<dynamic>? ?? [];
        print('  sectionListRenderer sections: ${sections.length}');
        for (var j = 0; j < sections.length; j++) {
          final section = sections[j] as Map<String, dynamic>;
          final isr = section['itemSectionRenderer'] as Map<String, dynamic>?;
          if (isr != null) {
            final isrContents = isr['contents'] as List<dynamic>? ?? [];
            for (final c in isrContents) {
              final cm = c as Map<String, dynamic>;
              if (cm.containsKey('shelfRenderer')) {
                final shelf = cm['shelfRenderer'] as Map<String, dynamic>;
                final titleRuns = (shelf['title'] as Map<String, dynamic>?)?['runs'] as List<dynamic>?;
                final shelfTitle = titleRuns?.isNotEmpty == true
                    ? (titleRuns![0] as Map<String, dynamic>)['text']
                    : 'N/A';
                final hr = (shelf['content'] as Map<String, dynamic>?)?['horizontalListRenderer'] as Map<String, dynamic>?;
                final items = hr?['items'] as List<dynamic>? ?? [];
                print('  Section $j shelf: "$shelfTitle" items=${items.length}');
                if (items.isNotEmpty) {
                  final first = items[0] as Map<String, dynamic>;
                  print('    First item keys: ${first.keys.toList()}');
                  if (first.containsKey('lockupViewModel')) {
                    final lvm = first['lockupViewModel'] as Map<String, dynamic>;
                    print('    contentType: ${lvm['contentType']}');
                    print('    contentId: ${lvm['contentId']}');
                  }
                }
              } else {
                print('  Section $j ISR content keys: ${cm.keys.toList()}');
              }
            }
          }
        }
      }
    }
  }

  httpClient.close();
}
