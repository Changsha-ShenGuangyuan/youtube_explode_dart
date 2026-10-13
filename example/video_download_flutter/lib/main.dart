import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
/*
import 'package:downloads_path_provider/downloads_path_provider.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter VideoDownload Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({super.key, required this.title});

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final textController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'Insert the video id or url',
            ),
            TextField(controller: textController),
            ElevatedButton(
              child: const Text('Download'),
              onPressed: () async {
                // Here you should validate the given input or else an error
                // will be thrown.
                final yt = YoutubeExplode();
                final id = VideoId(textController.text.trim());
                final video = await yt.videos.get(id);

                // Display info about this video.
                await showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      content: Text(
                        'Title: ${video.title}, Duration: ${video.duration}',
                      ),
                    );
                  },
                );

                // Request permission to write in an external directory.
                // (In this case downloads)
                await Permission.storage.request();

                // Get the streams manifest and the audio track.
                final manifest = await yt.videos.streamsClient.getManifest(id);
                final audio = manifest.audioOnly.last;

                // Build the directory.
                final dir = await DownloadsPathProvider.downloadsDirectory;
                final filePath = path.join(
                  dir.uri.toFilePath(),
                  '${video.id}.${audio.container.name}',
                );

                // Open the file to write.
                final file = File(filePath);
                final fileStream = file.openWrite();

                // Pipe all the content of the stream into our file.
                await yt.videos.streamsClient.get(audio).pipe(fileStream);
                /*
                  If you want to show a % of download, you should listen
                  to the stream instead of using `pipe` and compare
                  the current downloaded streams to the totalBytes,
                  see an example ii example/video_download.dart
                   */

                // Close the file.
                await fileStream.flush();
                await fileStream.close();

                // Show that the file was downloaded.
                await showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      content:
                          Text('Download completed and saved to: $filePath'),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
*/

void main() async {
  // testRelease();
  testVideos();
  // testPlaylistVideos();
  return;

  final yt = YoutubeExplode();
/*
  final searchList =
      await yt.search.searchContent("30", filter: TypeFilters.playlist);
  print(searchList);
  for (final result in searchList) {
    if (result is SearchPlaylist) {
      final channelId = searchList.channelIdForPlaylist(result.id.value);
      final name = searchList.authorNameForPlaylist(result.id.value);
      print('${name} → channelId: $channelId');
    }
  }*/
/*
  final playlist = await yt.playlists
      .customGet(PlaylistId('PLZGztNTIcGATcdR2Hx0TWEvtvssWe8PXk'));
  print(playlist.title);
  print(playlist.author);
  print(playlist.authorChannelId);
*/
  // final video = await yt.videos.get(id);
  // print(video.title);

//UCqECaJ8Gagnn7YCbPEzWH6g
//UCsRM0YB_dabtEPGPTKo-gcw
  // ChannelReleasesList playlists =
  //     await yt.channels.getReleaseListsFromPage("UCqECaJ8Gagnn7YCbPEzWH6g");
  // for (var element in playlists) {
  //   debugPrint("playlist--${element.toString()}");
  // }

  // final playlists2 = await playlists.nextPage();
  // for (var element in playlists2!) {
  //   debugPrint("playlist2--${element.toString()}");
  // }

  /*
  final channel =
      await yt.channels.customGet(ChannelId("UCsRM0YB_dabtEPGPTKo-gcw"));
  debugPrint("channel--${channel.videoCounts} ${channel.subscribers}");
  */

  final playlists =
      await yt.channels.getPlaylistsFromPage('UCvL3nX_cdCaDFyo8GSOsm7A');
  for (var element in playlists) {
    debugPrint("playlist--${element.toString()}");

    // final playlist22 =
    //     await yt.playlists.customGet(PlaylistId(element.id.value));
    // try {
    //   var videos = await yt.playlists.getVideos(element.id.value).toList();
    //   for (var element in videos) {
    //     debugPrint("video--${element.toString()}");
    //   }
    // } catch (e) {}
  }
  // debugPrint("playlist--${playlists[1].toString()}");

  final page2 = await playlists.nextPage(); // null 表示没有更多数据
  if (page2 != null && page2.isNotEmpty) {
    for (var element in page2) {
      debugPrint("playlist2--${element.toString()}");
    }
  }

  final page3 = await page2?.nextPage(); // null 表示没有更多数据
  if (page3 != null && page3.isNotEmpty) {
    for (var element in page3) {
      debugPrint("playlist3--${element.toString()}");
    }
  }

  final page4 = await page3?.nextPage(); // null 表示没有更多数据
  if (page4 != null && page4.isNotEmpty) {
    for (var element in page4) {
      debugPrint("playlist4--${element.toString()}");
    }
  }

  final page5 = await page4?.nextPage(); // null 表示没有更多数据
  if (page5 != null && page5.isNotEmpty) {
    for (var element in page5) {
      debugPrint("playlist5--${element.toString()}");
    }
  }

  debugPrint("done");
}

void testRelease() async {
  final yt = YoutubeExplode();
  final playlists =
      await yt.channels.getReleaseListsFromPage('UCvL3nX_cdCaDFyo8GSOsm7A');
  for (var element in playlists) {
    debugPrint("playlist--${element.toString()}");

    // final playlist22 =
    //     await yt.playlists.customGet(PlaylistId(element.id.value));
    // try {
    //   var videos = await yt.playlists.getVideos(element.id.value).toList();
    //   for (var element in videos) {
    //     debugPrint("video--${element.toString()}");
    //   }
    // } catch (e) {}
  }
  // debugPrint("playlist--${playlists[1].toString()}");

  final page2 = await playlists.nextPage(); // null 表示没有更多数据
  if (page2 != null && page2.isNotEmpty) {
    for (var element in page2) {
      debugPrint("playlist2--${element.toString()}");
    }
  }

  final page3 = await page2?.nextPage(); // null 表示没有更多数据
  if (page3 != null && page3.isNotEmpty) {
    for (var element in page3) {
      debugPrint("playlist3--${element.toString()}");
    }
  }

  final page4 = await page3?.nextPage(); // null 表示没有更多数据
  if (page4 != null && page4.isNotEmpty) {
    for (var element in page4) {
      debugPrint("playlist4--${element.toString()}");
    }
  }

  final page5 = await page4?.nextPage(); // null 表示没有更多数据
  if (page5 != null && page5.isNotEmpty) {
    for (var element in page5) {
      debugPrint("playlist5--${element.toString()}");
    }
  }
}

void testVideos() async {
  final yt = YoutubeExplode();
  final playlists =
      await yt.channels.getUploadsFromPage("UC5OrDvL9DscpcAstz7JnQGA");
  for (var element in playlists) {
    debugPrint("playlist--${element.toString()}");

    // final playlist22 =
    //     await yt.playlists.customGet(PlaylistId(element.id.value));
    // try {
    //   var videos = await yt.playlists.getVideos(element.id.value).toList();
    //   for (var element in videos) {
    //     debugPrint("video--${element.toString()}");
    //   }
    // } catch (e) {}
  }
  // debugPrint("playlist--${playlists[1].toString()}");

  final page2 = await playlists.nextPage(); // null 表示没有更多数据
  if (page2 != null && page2.isNotEmpty) {
    for (var element in page2) {
      debugPrint("playlist2--${element.toString()}");
    }
  }

  final page3 = await page2?.nextPage(); // null 表示没有更多数据
  if (page3 != null && page3.isNotEmpty) {
    for (var element in page3) {
      debugPrint("playlist3--${element.toString()}");
    }
  }

  final page4 = await page3?.nextPage(); // null 表示没有更多数据
  if (page4 != null && page4.isNotEmpty) {
    for (var element in page4) {
      debugPrint("playlist4--${element.toString()}");
    }
  }

  final page5 = await page4?.nextPage(); // null 表示没有更多数据
  if (page5 != null && page5.isNotEmpty) {
    for (var element in page5) {
      debugPrint("playlist5--${element.toString()}");
    }
  }
}

void testPlaylistVideos() async {
  final yt = YoutubeExplode();
  // final playlist22 = await yt.playlists
  //     .customGet(PlaylistId("PL2JtvykrieUxaLXkeuXRHb-pJB9XpVWtd"));
  try {
    var videos = await yt.playlists
        .getVideos("PL2JtvykrieUxaLXkeuXRHb-pJB9XpVWtd")
        .toList();
    for (var element in videos) {
      debugPrint("video--${element.toString()}");
    }
  } catch (e) {
    debugPrint("e--${e}");
  }
}
