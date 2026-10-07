import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Lecteur audio pour répéter : lecture, avance/recul de 10 s, vitesse, boucle.
class AudioPlayerBar extends StatefulWidget {
  final String url;

  const AudioPlayerBar({super.key, required this.url});

  @override
  State<AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends State<AudioPlayerBar> {
  final _player = AudioPlayer();
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.setUrl(widget.url).catchError((Object e) {
      if (mounted) setState(() => _error = 'Lecture audio impossible');
      return null;
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  void _seekBy(int seconds) {
    final target = _player.position + Duration(seconds: seconds);
    final max = _player.duration ?? Duration.zero;
    _player.seek(target < Duration.zero ? Duration.zero : (target > max ? max : target));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ListTile(leading: const Icon(Icons.error), title: Text(_error!));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (context, snap) {
              final pos = snap.data ?? Duration.zero;
              final total = _player.duration ?? Duration.zero;
              return Row(children: [
                Text(_fmt(pos)),
                Expanded(
                  child: Slider(
                    value: pos.inMilliseconds.clamp(0, total.inMilliseconds).toDouble(),
                    max: total.inMilliseconds.toDouble().clamp(1, double.infinity),
                    onChanged: (v) => _player.seek(Duration(milliseconds: v.round())),
                  ),
                ),
                Text(_fmt(total)),
              ]);
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: const Icon(Icons.replay_10), onPressed: () => _seekBy(-10)),
              StreamBuilder<PlayerState>(
                stream: _player.playerStateStream,
                builder: (context, snap) {
                  final playing = snap.data?.playing ?? false;
                  return IconButton.filled(
                    iconSize: 32,
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    onPressed: playing ? _player.pause : _player.play,
                  );
                },
              ),
              IconButton(icon: const Icon(Icons.forward_10), onPressed: () => _seekBy(10)),
              StreamBuilder<LoopMode>(
                stream: _player.loopModeStream,
                builder: (context, snap) {
                  final looping = snap.data == LoopMode.one;
                  return IconButton(
                    tooltip: 'Répéter en boucle',
                    icon: Icon(looping ? Icons.repeat_one_on : Icons.repeat_one),
                    onPressed: () => _player.setLoopMode(looping ? LoopMode.off : LoopMode.one),
                  );
                },
              ),
              StreamBuilder<double>(
                stream: _player.speedStream,
                builder: (context, snap) {
                  final speed = snap.data ?? 1.0;
                  return PopupMenuButton<double>(
                    tooltip: 'Vitesse',
                    initialValue: speed,
                    onSelected: _player.setSpeed,
                    itemBuilder: (_) => [
                      for (final s in [0.5, 0.75, 1.0, 1.25])
                        PopupMenuItem(value: s, child: Text('×$s')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('×$speed'),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
