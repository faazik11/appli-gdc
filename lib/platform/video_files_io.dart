import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Vidéo choisie sur l'appareil, pas encore envoyée.
class PickedVideo {
  final Object handle;
  final String name;
  final int size;
  final String type;
  final int seconds;

  const PickedVideo({required this.handle, required this.name, required this.size, required this.type, this.seconds = 0});
}

Future<PickedVideo?> pickVideo() async {
  final f = await FilePicker.pickFile(type: FileType.video);
  if (f == null) return null;
  return PickedVideo(handle: f, name: f.name, size: await f.length() ?? 0, type: '');
}

/// Envoie la vidéo au lien signé ; lève une erreur si Cloudflare refuse.
Future<void> uploadVideo(PickedVideo v, String url, String type, void Function(double) onProgress) async {
  final bytes = await (v.handle as PlatformFile).readAsBytes();
  final r = await http.put(Uri.parse(url), headers: {'Content-Type': type}, body: bytes);
  if (r.statusCode >= 300) throw Exception('Cloudflare R2 a répondu ${r.statusCode}');
  onProgress(1);
}

void forgetVideo(PickedVideo v) {}

/// Hors navigateur : la vidéo s'ouvre dans le lecteur du téléphone.
Widget videoPlayer(String url) => Center(
      child: FilledButton.icon(
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Regarder la vidéo'),
        onPressed: () => launchUrl(Uri.parse(url)),
      ),
    );
