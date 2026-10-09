import 'dart:typed_data';

import 'package:appli_gdc/services/tones.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('La 440 et WAV valide', () {
    expect(Tones.frequency(0), 440);
    expect(Tones.frequency(-9), closeTo(261.63, 0.01)); // Do4
    final wav = Tones.note(440, seconds: 1);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(ByteData.sublistView(wav).getUint32(40, Endian.little), Tones.sampleRate * 2);
  });

  test('tous les sons du diapason sont valides et au même volume', () {
    for (final t in Timbre.values) {
      final wav = Tones.note(261.63, seconds: 1, timbre: t);
      final data = ByteData.sublistView(wav);
      var peak = 0;
      for (var i = 44; i < wav.length; i += 2) {
        final v = data.getInt16(i, Endian.little).abs();
        if (v > peak) peak = v;
      }
      expect(peak, inInclusiveRange(20000, 23000), reason: t.name);
    }
  });

  test('boucle de métronome à la bonne durée', () {
    final wav = Tones.metronome(120, 4, bars: 2);
    // 8 temps à 0,5 s = 4 s
    expect((wav.length - 44) / 2 / Tones.sampleRate, closeTo(4, 0.01));
  });
}
