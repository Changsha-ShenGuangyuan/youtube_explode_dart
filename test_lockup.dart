// Verify view count parsing
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final yt = YoutubeExplode();

  final uploads = await yt.channels
      .getUploadsFromPage("UC5OrDvL9DscpcAstz7JnQGA");

  print('Found ${uploads.length} videos');
  for (var i = 0; i < uploads.length && i < 10; i++) {
    final v = uploads[i];
    print('  [$i] ${v.title}');
    print('       id=${v.id} duration=${v.duration}');
    print('       views=${v.engagement.viewCount}');
    print('       uploadDate=${v.uploadDateRaw}');
  }

  // Test pagination
  print('\n--- Testing pagination ---');
  final page2 = await uploads.nextPage();
  if (page2 != null) {
    print('Page 2: ${page2.length} videos');
    for (var i = 0; i < page2.length && i < 3; i++) {
      final v = page2[i];
      print('  [$i] ${v.title} (${v.id})');
    }
  } else {
    print('No page 2 (null)');
  }

  yt.close();
}
