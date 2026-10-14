import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../platform/device_files.dart';

/// Apparence choisie sur ce téléphone : claire, sombre, ou comme le téléphone (par défaut).
class Appearance {
  static final mode = ValueNotifier(ThemeMode.system);
  static const _key = 'reglages/apparence';

  /// Lu avant l'ouverture de l'appli, pour ne pas voir l'autre thème une fraction de seconde.
  static Future<void> load() async {
    try {
      final saved = await deviceGet(_key);
      if (saved == null || saved.isEmpty) return;
      final name = utf8.decode(saved);
      mode.value = ThemeMode.values.firstWhere((m) => m.name == name, orElse: () => ThemeMode.system);
    } catch (_) {
      // Sans réglage enregistré, on suit le téléphone.
    }
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    await devicePut(_key, Uint8List.fromList(utf8.encode(m.name)));
  }

  static String label(ThemeMode m) => switch (m) {
        ThemeMode.system => 'Comme le téléphone',
        ThemeMode.light => 'Clair',
        ThemeMode.dark => 'Sombre',
      };

  /// Fenêtre de choix de l'apparence.
  static Future<void> choose(BuildContext context) => showDialog<void>(
        context: context,
        builder: (ctx) => ValueListenableBuilder<ThemeMode>(
          valueListenable: mode,
          builder: (ctx, current, _) => AlertDialog(
            title: const Text('Apparence'),
            contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
            content: RadioGroup<ThemeMode>(
              groupValue: current,
              onChanged: (m) {
                if (m != null) set(m);
              },
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final (m, icon) in [
                  (ThemeMode.system, Icons.brightness_auto_rounded),
                  (ThemeMode.light, Icons.light_mode_rounded),
                  (ThemeMode.dark, Icons.dark_mode_rounded),
                ])
                  RadioListTile<ThemeMode>(
                    value: m,
                    title: Text(label(m)),
                    subtitle: m == ThemeMode.system ? const Text('Suit le réglage clair ou sombre du téléphone') : null,
                    secondary: Icon(icon),
                  ),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))],
          ),
        ),
      );
}
