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

  test('boucle de métronome à la bonne durée', () {
    final wav = Tones.metronome(120, 4, bars: 2);
    // 8 temps à 0,5 s = 4 s
    expect((wav.length - 44) / 2 / Tones.sampleRate, closeTo(4, 0.01));
  });
}
