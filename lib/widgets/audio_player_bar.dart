import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Lecteur audio pour répéter : lecture, avance/recul de 10 s, vitesse, boucle.
///
/// Avec plusieurs fichiers ([parts]), ils sont lus l'un après l'autre comme un seul enregistrement :
/// une seule barre de temps du début de la première partie à la fin de la dernière.
class AudioPlayerBar extends StatefulWidget {
  final List<String> urls;

  /// Durée connue d'avance (certains enregistrements ne l'indiquent pas eux-mêmes).
  final Duration? duration;

  /// Durée connue de chaque partie, quand il y en a plusieurs.
  final List<Duration?> partDurations;

  AudioPlayerBar({super.key, required String url, this.duration})
      : urls = [url],
        partDurations = const [];

  const AudioPlayerBar.parts({super.key, required this.urls, this.partDurations = const [], this.duration});

  @override
  State<AudioPlayerBar> createState() => AudioPlayerBarState();
}

class AudioPlayerBarState extends State<AudioPlayerBar> {
  final _player = AudioPlayer();
  String? _error;

  String get _url => widget.urls.first;

  bool get _multi => widget.urls.length > 1;

  @override
  void initState() {
    super.initState();
    final load = _multi
        ? _player.setAudioSources([for (final u in widget.urls) AudioSource.uri(Uri.parse(u))])
        : _player.setUrl(_url);
    load.catchError((Object e) {
      if (mounted) setState(() => _error = 'Lecture audio impossible');
      return null;
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    if (d.inHours == 0) return '${d.inMinutes}:$s';
    return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:$s';
  }

  /// Durée d'une partie : celle lue par le lecteur, sinon celle connue d'avance.
  Duration _partLength(int i) {
    final seq = _player.sequence;
    final d = i < seq.length ? seq[i].duration : null;
    if (d != null && d > Duration.zero) return d;
    if (i == _player.currentIndex && (_player.duration ?? Duration.zero) > Duration.zero) return _player.duration!;
    return (i < widget.partDurations.length ? widget.partDurations[i] : null) ?? Duration.zero;
  }

  Duration get _total {
    if (_multi) {
      var t = Duration.zero;
      for (var i = 0; i < widget.urls.length; i++) {
        t += _partLength(i);
      }
      return t == Duration.zero ? (widget.duration ?? Duration.zero) : t;
    }
    final d = _player.duration;
    return (d == null || d == Duration.zero) ? (widget.duration ?? Duration.zero) : d;
  }

  /// Début de la partie [index] sur la barre de temps commune.
  Duration _offset(int index) {
    var t = Duration.zero;
    for (var i = 0; i < index; i++) {
      t += _partLength(i);
    }
    return t;
  }

  Duration get _position => _multi ? _offset(_player.currentIndex ?? 0) + _player.position : _player.position;

  void _seekTo(Duration target) {
    final max = _total;
    if (target < Duration.zero) target = Duration.zero;
    if (target > max) target = max;
    if (!_multi) {
      _player.seek(target);
      return;
    }
    var start = Duration.zero;
    for (var i = 0; i < widget.urls.length; i++) {
      final len = _partLength(i);
      if (target < start + len || i == widget.urls.length - 1) {
        _player.seek(target - start, index: i);
        return;
      }
      start += len;
    }
  }

  /// Moment écouté, sur la barre de temps commune (pour poser un repère).
  Duration get position => _position;

  /// Va à [target] et lance la lecture (repères).
  void playFrom(Duration target) {
    _seekTo(target);
    _player.play();
  }

  void _seekBy(int seconds) => _seekTo(_position + Duration(seconds: seconds));

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
              final pos = _multi ? _position : (snap.data ?? Duration.zero);
              final total = _total;
              return Row(children: [
                Text(_fmt(pos)),
                Expanded(
                  child: Slider(
                    value: pos.inMilliseconds.clamp(0, total.inMilliseconds).toDouble(),
                    max: total.inMilliseconds.toDouble().clamp(1, double.infinity),
                    onChanged: (v) => _seekTo(Duration(milliseconds: v.round())),
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
