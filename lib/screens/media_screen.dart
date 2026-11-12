import 'package:flutter/material.dart';

import '../services/agenda.dart';
import '../services/workshop.dart';
import 'recordings_screen.dart';
import 'videos_screen.dart';

/// Onglet « Enregistrements » : les répétitions enregistrées et les vidéos des prestations.
class MediaScreen extends StatelessWidget {
  final WorkBackend backend;
  final AgendaBackend agenda;
  final bool canEdit;

  const MediaScreen({super.key, required this.backend, required this.agenda, required this.canEdit});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Enregistrements'),
            bottom: const TabBar(tabs: [Tab(text: 'Répétitions'), Tab(text: 'Vidéos des prestations')]),
          ),
          body: TabBarView(children: [
            RecordingsScreen(backend: backend, agenda: agenda, canEdit: canEdit),
            VideosScreen(agenda: agenda, canEdit: canEdit),
          ]),
        ),
      );
}
