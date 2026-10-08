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

  /// Son doux et tenu (fondamentale + harmoniques légères), avec attaque et extinction.
  static Uint8List note(double freq, {double seconds = 2.5}) {
    final n = (seconds * sampleRate).round();
    final s = Float64List(n);
    final fade = (0.04 * sampleRate).round();
    final release = (0.4 * sampleRate).round();
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      var v = sin(2 * pi * freq * t) + 0.3 * sin(4 * pi * freq * t) + 0.12 * sin(6 * pi * freq * t);
      var env = 1.0;
      if (i < fade) env = i / fade;
      if (i > n - release) env = (n - i) / release;
      s[i] = 0.45 * v / 1.42 * env;
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
