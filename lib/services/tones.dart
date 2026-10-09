import 'dart:math';
import 'dart:typed_data';

/// Génère de petits fichiers WAV (mono, 16 bits) pour le diapason et le métronome.
class Tones {
  static const sampleRate = 22050;

  static Uint8List _wav(Float64List samples) {
    final data = ByteData(44 + samples.length * 2);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32000).round(), Endian.little);
    }
    return data.buffer.asUint8List();
  }

  /// Fréquence d'une note : [semitonesFromA4] demi-tons au-dessus (ou au-dessous) du La de référence.
  static double frequency(int semitonesFromA4, {double a4 = 440}) => a4 * pow(2, semitonesFromA4 / 12);

  /// Note du diapason dans le [timbre] choisi, avec attaque et extinction.
  static Uint8List note(double freq, {double seconds = 2.5, Timbre timbre = Timbre.doux}) {
    final n = (seconds * sampleRate).round();
    final s = Float64List(n);
    final rnd = Random(7);
    // Voix « Aah » : poids des harmoniques selon les formants de la voyelle a.
    double formant(double f) {
      double peak(double centre, double width, double gain) => gain / (1 + pow((f - centre) / width, 2));
      return peak(730, 110, 1.0) + peak(1090, 120, 0.55) + peak(2440, 200, 0.25) + 0.04;
    }

    final voice = [for (var h = 1; h * freq < sampleRate / 2.2 && h <= 40; h++) (h, formant(h * freq))];
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final w = 2 * pi * freq * t;
      double v;
      switch (timbre) {
        case Timbre.doux:
          v = sin(w) + 0.3 * sin(2 * w) + 0.12 * sin(3 * w);
        case Timbre.piano:
          // Corde frappée : harmoniques légèrement décalées qui s'éteignent plus vite que la fondamentale.
          v = 0.0;
          for (var h = 1; h <= 8; h++) {
            final stretch = h * (1 + 0.0004 * h * h);
            v += sin(w * stretch) * exp(-t * (0.9 + 0.55 * h)) / pow(h, 1.1);
          }
          v *= 1.6;
        case Timbre.orgue:
          // Jeux d'orgue : fondamentale, octaves et quinte (pas d'octave grave : la note resterait juste mais paraîtrait plus basse).
          v = sin(w) + 0.6 * sin(2 * w) + 0.35 * sin(3 * w) + 0.3 * sin(4 * w) + 0.12 * sin(8 * w);
        case Timbre.flute:
          final vib = 1 + 0.004 * sin(2 * pi * 5 * t) * min(1.0, t / 0.6);
          final wv = 2 * pi * freq * vib * t;
          v = sin(wv) + 0.18 * sin(2 * wv) + 0.05 * sin(3 * wv) + 0.06 * (rnd.nextDouble() * 2 - 1);
        case Timbre.fourche:
          // Diapason à fourche : son pur.
          v = sin(w);
        case Timbre.voix:
          final vib = 1 + 0.006 * sin(2 * pi * 5.5 * t) * min(1.0, t / 0.5);
          final wv = 2 * pi * freq * vib * t;
          v = 0.0;
          for (final (h, g) in voice) {
            v += g * sin(h * wv);
          }
      }
      s[i] = v;
    }
    // Volume identique pour tous les sons, attaque et extinction en douceur.
    var peak = 0.0;
    for (final v in s) {
      peak = max(peak, v.abs());
    }
    final attack = ((timbre == Timbre.piano ? 0.004 : (timbre == Timbre.voix || timbre == Timbre.flute ? 0.12 : 0.04)) *
            sampleRate)
        .round();
    final release = (0.4 * sampleRate).round();
    for (var i = 0; i < n; i++) {
      var env = 1.0;
      if (i < attack) env = i / attack;
      if (i > n - release) env = min(env, (n - i) / release);
      s[i] = 0.7 * s[i] / (peak == 0 ? 1 : peak) * env;
    }
    return _wav(s);
  }

  /// Une boucle de métronome : [bars] mesures de [beats] temps, le premier temps accentué.
  static Uint8List metronome(int bpm, int beats, {int bars = 4}) {
    final beatLen = (60 / bpm * sampleRate).round();
    final total = beatLen * beats * bars;
    final s = Float64List(total);
    final click = (0.03 * sampleRate).round();
    for (var b = 0; b < beats * bars; b++) {
      final accent = b % beats == 0;
      final freq = accent ? 1760.0 : 1100.0;
      final start = b * beatLen;
      for (var i = 0; i < click && start + i < total; i++) {
        final env = exp(-i / (click / 5));
        s[start + i] = (accent ? 0.9 : 0.6) * sin(2 * pi * freq * i / sampleRate) * env;
      }
    }
    return _wav(s);
  }
}

/// Sons proposés par le diapason.
enum Timbre {
  doux('Doux'),
  piano('Piano'),
  orgue('Orgue'),
  flute('Flûte'),
  voix('Voix'),
  fourche('Diapason');

  final String label;
  const Timbre(this.label);
}
