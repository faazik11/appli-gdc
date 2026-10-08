import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/tones.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Diapason et métronome.
class ToolsScreen extends StatelessWidget {
  final int initialTab;

  const ToolsScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Outils'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.tune_rounded), text: 'Diapason'),
            Tab(icon: Icon(Icons.timer_outlined), text: 'Métronome'),
          ]),
        ),
        body: const TabBarView(children: [_Tuner(), _Metronome()]),
      ),
    );
  }
}

AudioSource _wavSource(List<int> bytes) => AudioSource.uri(Uri.dataFromBytes(bytes, mimeType: 'audio/wav'));

// ---------- Diapason ----------

class _Tuner extends StatefulWidget {
  const _Tuner();

  @override
  State<_Tuner> createState() => _TunerState();
}

class _TunerState extends State<_Tuner> {
  static const _names = ['Do', 'Do♯', 'Ré', 'Mi♭', 'Mi', 'Fa', 'Fa♯', 'Sol', 'Sol♯', 'La', 'Si♭', 'Si'];
  final _player = AudioPlayer();
  int _octave = 4;
  double _a4 = 440;
  bool _hold = false;
  int? _playing;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _play(int index) async {
    // index 0 = Do de l'octave choisie ; le La4 est à 9 demi-tons au-dessus du Do4.
    final semis = (_octave - 4) * 12 + index - 9;
    final freq = Tones.frequency(semis, a4: _a4);
    setState(() => _playing = index);
    try {
      await _player.stop();
      await _player.setAudioSource(_wavSource(Tones.note(freq, seconds: _hold ? 4 : 2.5)));
      await _player.setLoopMode(_hold ? LoopMode.one : LoopMode.off);
      await _player.play();
    } finally {
      if (mounted && !_hold) setState(() => _playing = null);
    }
  }

  Future<void> _stop() async {
    await _player.stop();
    if (mounted) setState(() => _playing = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return ListView(padding: const EdgeInsets.fromLTRB(0, 16, 0, 40), children: [
      ContentWidth(
        maxWidth: 640,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Touche une note pour l\'entendre et donner le ton au groupe.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: width >= 500 ? 6 : 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.1,
              children: [
                for (final (i, n) in _names.indexed)
                  Material(
                    color: _playing == i
                        ? AppColors.gold
                        : (const {1, 3, 6, 8, 10}.contains(i) ? AppColors.aubergine : AppColors.aubergineLight),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _playing == i && _hold ? _stop() : _play(i),
                      child: Center(
                        child: Text('$n${_octave == 4 ? '' : _octave}',
                            style: TextStyle(
                                fontFamily: 'DMSerifDisplay',
                                fontSize: 24,
                                color: _playing == i ? AppColors.aubergine : Colors.white)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Octave', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 3, label: Text('Grave')),
                ButtonSegment(value: 4, label: Text('Médium')),
                ButtonSegment(value: 5, label: Text('Aigu')),
              ],
              selected: {_octave},
              onSelectionChanged: (s) => setState(() => _octave = s.first),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Son tenu'),
              subtitle: const Text('La note continue jusqu\'à ce que tu la touches à nouveau'),
              value: _hold,
              onChanged: (v) {
                setState(() => _hold = v);
                _stop();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('La de référence'),
              subtitle: Text('${_a4.round()} Hz'),
              trailing: SegmentedButton<double>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 440, label: Text('440')),
                  ButtonSegment(value: 442, label: Text('442')),
                ],
                selected: {_a4},
                onSelectionChanged: (s) => setState(() => _a4 = s.first),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ---------- Métronome ----------

class _Metronome extends StatefulWidget {
  const _Metronome();

  @override
  State<_Metronome> createState() => _MetronomeState();
}

class _MetronomeState extends State<_Metronome> {
  final _player = AudioPlayer();
  int _bpm = 80;
  int _beats = 4;
  bool _running = false;
  int _beat = -1;
  Timer? _ticker;
  final _taps = <DateTime>[];

  @override
  void dispose() {
    _ticker?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final barSeconds = 60 / _bpm * _beats;
    final bars = (8 / barSeconds).ceil().clamp(1, 32);
    await _player.stop();
    await _player.setAudioSource(_wavSource(Tones.metronome(_bpm, _beats, bars: bars)));
    await _player.setLoopMode(LoopMode.one);
    _player.play();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 30), (_) {
      // Le témoin visuel suit la position réelle de la lecture.
      final ms = _player.position.inMilliseconds;
      final beat = (ms / (60000 / _bpm)).floor() % _beats;
      if (beat != _beat && mounted) setState(() => _beat = beat);
    });
    setState(() => _running = true);
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    await _player.stop();
    if (mounted) {
      setState(() {
        _running = false;
        _beat = -1;
      });
    }
  }

  void _setBpm(int bpm) {
    setState(() => _bpm = bpm.clamp(30, 240));
    if (_running) _start();
  }

  void _tap() {
    final now = DateTime.now();
    _taps.removeWhere((t) => now.difference(t) > const Duration(seconds: 3));
    _taps.add(now);
    if (_taps.length >= 2) {
      final gaps = [for (var i = 1; i < _taps.length; i++) _taps[i].difference(_taps[i - 1]).inMilliseconds];
      final avg = gaps.reduce((a, b) => a + b) / gaps.length;
      _setBpm((60000 / avg).round());
    }
  }

  static String _tempoName(int bpm) => switch (bpm) {
        < 60 => 'Largo',
        < 76 => 'Adagio',
        < 108 => 'Andante',
        < 120 => 'Moderato',
        < 168 => 'Allegro',
        _ => 'Presto',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(0, 16, 0, 40), children: [
      ContentWidth(
        maxWidth: 640,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(24)),
              child: Column(children: [
                Text('$_bpm', style: const TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 72, height: 1, color: Colors.white)),
                Text('battements par minute · ${_tempoName(_bpm)}',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.goldLight)),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < _beats; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 80),
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: i == 0 ? 22 : 16,
                      height: i == 0 ? 22 : 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _beat == i ? AppColors.gold : Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
            Row(children: [
              IconButton.filledTonal(onPressed: () => _setBpm(_bpm - 1), icon: const Icon(Icons.remove_rounded)),
              Expanded(
                child: Slider(
                  value: _bpm.toDouble(),
                  min: 30,
                  max: 240,
                  onChanged: (v) => setState(() => _bpm = v.round()),
                  onChangeEnd: (v) => _setBpm(v.round()),
                ),
              ),
              IconButton.filledTonal(onPressed: () => _setBpm(_bpm + 1), icon: const Icon(Icons.add_rounded)),
            ]),
            const SizedBox(height: 8),
            Text('Temps par mesure', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
                ButtonSegment(value: 4, label: Text('4')),
                ButtonSegment(value: 6, label: Text('6')),
              ],
              selected: {_beats},
              onSelectionChanged: (s) {
                setState(() => _beats = s.first);
                if (_running) _start();
              },
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.touch_app_rounded),
                  label: const Text('Taper le tempo'),
                  onPressed: _tap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: Icon(_running ? Icons.stop_rounded : Icons.play_arrow_rounded),
                  label: Text(_running ? 'Arrêter' : 'Démarrer'),
                  onPressed: _running ? _stop : _start,
                ),
              ),
            ]),
          ]),
        ),
      ),
    ]);
  }
}
