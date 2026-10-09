// Démo hors ligne pour les captures d'écran : `flutter build web -t tool/demo_main.dart`
// puis ouvrir index.html?screen=home|songs|agenda|booklets|members|login&theme=dark (&view=...)
import 'package:appli_gdc/models.dart';
import 'package:appli_gdc/services/agenda.dart';
import 'package:appli_gdc/services/file_store.dart';
import 'package:appli_gdc/services/workshop.dart';
import 'dart:typed_data';
import 'package:appli_gdc/screens/auth_screen.dart';
import 'package:appli_gdc/screens/home_screen.dart';
import 'package:appli_gdc/screens/inventory_screen.dart';
import 'package:appli_gdc/screens/recordings_screen.dart';
import 'package:appli_gdc/screens/members_screen.dart';
import 'package:appli_gdc/screens/song_screen.dart';
import 'package:appli_gdc/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';

const _categories = [
  Category(id: 1, name: 'Chants Français'),
  Category(id: 2, name: 'Chants Arabe'),
  Category(id: 3, name: 'Chants Mariage'),
  Category(id: 4, name: 'Chants International'),
  Category(id: 5, name: 'Livrets'),
];

final _now = DateTime.now();
Song _song(String id, String title, int cat,
        {bool pdf = true, bool yt = false, bool audio = false, List<String> tags = const [], int ago = 1}) =>
    Song(
      id: id,
      title: title,
      categoryId: cat,
      lyricsPdfPath: pdf ? 'x' : null,
      youtubeUrl: yt ? 'https://youtu.be/x' : null,
      audioPath: audio ? 'x' : null,
      tags: tags,
      createdAt: _now.subtract(Duration(hours: ago)),
    );

final _songs = [
  _song('1', 'Ave Maria', 1, yt: true, tags: ['Messe', 'Méditation'], ago: 2),
  _song('2', 'Tala al badru alayna', 2, yt: true, audio: true, tags: ['Fête'], ago: 5),
  _song('3', 'Amazing Grace', 4, audio: true, tags: ['Gospel'], ago: 9),
  _song('4', 'Hymne à l\'amour', 3, yt: true, tags: ['Entrée des mariés'], ago: 20),
  _song('5', 'Les Champs-Élysées', 1, yt: true, ago: 30),
  _song('6', 'Oh Happy Day', 4, yt: true, audio: true, tags: ['Gospel', 'Final'], ago: 40),
  _song('7', 'Ya Habibi', 2, audio: true, ago: 50),
  _song('8', 'Hallelujah', 4, yt: true, tags: ['Leonard Cohen'], ago: 60),
];

final _booklets = [
  Booklet(id: 'b1', title: 'Mariage de Sarah et Karim', eventDate: DateTime(2026, 11, 14), pdfPath: 'x', parts: [
    BookletPart(name: 'Entrée', songIds: ['4', '1']),
    BookletPart(name: 'Sortie', songIds: ['6']),
  ]),
  Booklet(id: 'b2', title: 'Concert de Noël', eventDate: DateTime(2026, 12, 20), pdfPath: 'x', parts: [
    BookletPart(name: '', songIds: ['1', '3', '8', '6', '5']),
  ]),
  Booklet(id: 'b3', title: 'Répertoire 2025', pdfPath: 'x'),
];

final _profiles = [
  const Profile(id: 'p1', fullName: 'Rayan Bounoua', role: MemberRole.admin),
  const Profile(id: 'p2', fullName: 'Inès Haddad', role: MemberRole.chef),
  const Profile(id: 'p3', fullName: 'Yanis Morel', role: MemberRole.membre),
  const Profile(id: 'p4', fullName: 'Lina Benali', role: MemberRole.membre),
  const Profile(id: 'p5', fullName: 'Thomas Girard', role: MemberRole.enAttente),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FileStore.instance.download =
      (_, path) async => (await http.get(Uri.base.resolve(path == 'x' ? 'sample.pdf' : path))).bodyBytes;
  await initializeDateFormatting('fr_FR');
  final q = Uri.base.queryParameters;
  final screen = q['screen'] ?? 'home';
  final tab = const {'home': 0, 'songs': 1, 'agenda': 2, 'repetes': 3, 'materiel': 4, 'members': 5}[screen] ?? 0;
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('fr', 'FR'),
    supportedLocales: const [Locale('fr', 'FR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    themeMode: q['theme'] == 'dark' ? ThemeMode.dark : ThemeMode.light,
    home: screen == 'inventory'
        ? InventoryScreen(backend: _work, canEdit: q['as'] != 'membre')
        : screen == 'recordings'
            ? RecordingsScreen(backend: _work, agenda: _DemoAgenda(null), canEdit: q['as'] != 'membre')
            : screen == 'recorder'
                ? RecorderScreen(backend: _work, agenda: _DemoAgenda(null))
                : screen == 'login'
                    ? const AuthScreen()
                    : screen == 'song'
                        ? SongScreen(
                            song: Song(
                              id: '1',
                              title: 'Ave Maria',
                              categoryId: 1,
                              lyricsPdfPath: 'sample.pdf',
                              youtubeUrl: q['yt'] == '1' ? 'https://www.youtube.com/watch?v=2bosouX_d8Y' : null,
                              audioPath: 'audio.mp3',
                              tags: const ['Messe'],
                              notes: 'Attention à l\'entrée des altos à la mesure 12.',
                            ),
                            category: _categories.first,
                            canEdit: true,
                            onEdit: () {},
                            signUrl: (_, path) async => Uri.base.resolve(path).toString(),
                          )
                        : HomeScreen(
                            profile: q['as'] == 'membre' ? _profiles[2] : _profiles.first,
                            initialTab: tab,
                            load: () async => LibraryData(_categories, _songs, _booklets),
                            agenda: _DemoAgenda(q['as'] == 'membre' ? 'p3' : null),
                            work: _work,
                            membersPanel: MembersPanel(load: () async => _profiles, setRole: (_, __) async {}),
                          ),
  ));
}

/// Agenda en mémoire pour la démo.
class _DemoAgenda implements AgendaBackend {
  /// Membre simple connecté : il ne reçoit que sa propre ligne, comme avec la vraie base.
  final String? memberId;

  _DemoAgenda(this.memberId);

  static DateTime _d(int days, int h, int m) {
    final t = DateTime.now();
    return DateTime(t.year, t.month, t.day + days, h, m);
  }

  static int _untilWeekday(int wd) => (wd - DateTime.now().weekday) % 7;

  final List<ChoirEvent> _events = [
    for (var w = 4; w >= 1; w--) ...[
      ChoirEvent(
        id: 'pw$w',
        kind: EventKind.repetition,
        startsAt: _d(_untilWeekday(DateTime.wednesday) - 7 * w, 20, 0),
        endsAt: _d(_untilWeekday(DateTime.wednesday) - 7 * w, 22, 0),
        location: 'Salle des fêtes de Narbonne',
        participants: [
          for (final (i, id) in ['p1', 'p2', 'p3', 'p4'].indexed)
            Participant(profileId: id, response: EventResponse.present, attended: (i + w) % 4 != 0),
        ],
      ),
      ChoirEvent(
        id: 'ps$w',
        kind: EventKind.repetition,
        startsAt: _d(_untilWeekday(DateTime.saturday) - 7 * w, 14, 30),
        endsAt: _d(_untilWeekday(DateTime.saturday) - 7 * w, 17, 0),
        location: 'Salle des fêtes de Narbonne',
        participants: [
          for (final (i, id) in ['p1', 'p2', 'p3', 'p4'].indexed)
            Participant(profileId: id, response: EventResponse.present, attended: i != 3 || w.isEven),
        ],
      ),
    ],
    ChoirEvent(
      id: 'pp1',
      kind: EventKind.prestation,
      title: 'Concert de la Saint-Michel',
      startsAt: _d(-12, 19, 0),
      location: 'Cathédrale Saint-Just',
      participants: const [
        Participant(profileId: 'p1', response: EventResponse.present, attended: true),
        Participant(profileId: 'p2', response: EventResponse.present, attended: true),
        Participant(profileId: 'p3', response: EventResponse.present, attended: true),
        Participant(profileId: 'p4', response: EventResponse.absent, attended: false),
      ],
    ),
    ChoirEvent(
      id: 'e1',
      kind: EventKind.repetition,
      songIds: const ['4', '2', '8'],
      startsAt: _d(_untilWeekday(DateTime.wednesday), 20, 0),
      endsAt: _d(_untilWeekday(DateTime.wednesday), 22, 0),
      location: 'Salle des fêtes de Narbonne',
      notes: 'On revoit Hymne à l\'amour et Tala al badru.',
      participants: const [
        Participant(profileId: 'p1', response: EventResponse.present),
        Participant(profileId: 'p2', response: EventResponse.present),
        Participant(profileId: 'p3', response: EventResponse.peutEtre),
      ],
    ),
    ChoirEvent(
      id: 'e2',
      kind: EventKind.repetition,
      startsAt: _d(_untilWeekday(DateTime.saturday), 14, 30),
      endsAt: _d(_untilWeekday(DateTime.saturday), 17, 0),
      location: 'Salle des fêtes de Narbonne',
      participants: const [Participant(profileId: 'p4', response: EventResponse.absent)],
    ),
    ChoirEvent(
      id: 'e3',
      kind: EventKind.prestation,
      bookletId: 'b1',
      title: 'Mariage de Sarah et Karim',
      startsAt: _d(_untilWeekday(DateTime.saturday) + 7, 18, 0),
      location: 'Domaine de Fontfroide',
      notes: 'Tenue noire et doré. Rendez-vous 17h15 sur le parking.',
      participants: const [
        Participant(profileId: 'p1', response: EventResponse.present),
        Participant(profileId: 'p2', response: EventResponse.present),
        Participant(profileId: 'p4', response: EventResponse.present),
      ],
    ),
  ];

  @override
  Future<List<ChoirEvent>> events() async => [
        for (final e in _events)
          e.copyWith(
            participants: memberId == null
                ? e.participants
                : [
                    for (final p in e.participants)
                      p.profileId == memberId ? p : Participant(profileId: p.profileId, response: p.response),
                  ],
            summary: EventSummary(
              present: e.count(EventResponse.present),
              peutEtre: e.count(EventResponse.peutEtre),
              absent: e.count(EventResponse.absent),
              attended: e.attendedCount,
              rollCallDone: e.rollCallDone,
            ),
          ),
      ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  @override
  Future<List<Profile>> members() async => _profiles.where((p) => p.isApproved).toList();

  @override
  Future<void> saveEvent(
      {String? id,
      required EventKind kind,
      String? title,
      required DateTime startsAt,
      DateTime? endsAt,
      String? location,
      String? notes,
      List<String> songIds = const [],
      String? bookletId}) async {
    final old = _events.where((e) => e.id == id).firstOrNull;
    _events.removeWhere((e) => e.id == id);
    _events.add(ChoirEvent(
        id: id ?? 'n${_events.length}',
        kind: kind,
        title: title,
        startsAt: startsAt,
        endsAt: endsAt,
        location: location,
        notes: notes,
        songIds: songIds,
        bookletId: bookletId,
        participants: old?.participants ?? const []));
  }

  final _announcements = [
    Announcement(
        id: 'a1',
        body:
            'Samedi on termine à 17h précises : la salle est réservée après nous. Pensez à apporter vos livrets du mariage !',
        authorId: 'p2',
        createdAt: DateTime.now().subtract(const Duration(hours: 3))),
    Announcement(
        id: 'a2',
        body: 'Bienvenue à Lina qui rejoint les altos 🎶',
        authorId: 'p1',
        createdAt: DateTime.now().subtract(const Duration(days: 2))),
  ];

  @override
  Future<List<Announcement>> announcements() async => [..._announcements];

  @override
  Future<void> postAnnouncement(String body) async => _announcements.insert(
      0, Announcement(id: 'a${_announcements.length + 1}', body: body, authorId: 'p1', createdAt: DateTime.now()));

  @override
  Future<void> deleteAnnouncement(String id) async => _announcements.removeWhere((a) => a.id == id);

  @override
  Future<void> deleteEvent(String id) async => _events.removeWhere((e) => e.id == id);

  void _update(String eventId, String profileId, Participant Function(Participant? old) f) {
    final i = _events.indexWhere((e) => e.id == eventId);
    final e = _events[i];
    final parts = [...e.participants.where((p) => p.profileId != profileId), f(e.participantOf(profileId))];
    _events[i] = e.copyWith(participants: parts);
  }

  @override
  Future<void> setResponse(String eventId, String profileId, EventResponse response) async =>
      _update(eventId, profileId, (o) => Participant(profileId: profileId, response: response, attended: o?.attended));

  @override
  Future<void> setAttended(String eventId, String profileId, bool? attended) async =>
      _update(eventId, profileId, (o) => Participant(profileId: profileId, response: o?.response, attended: attended));
}

final _work = _DemoWork();

/// Inventaire et enregistrements en mémoire pour la démo.
class _DemoWork implements WorkBackend {
  final _cats = [
    const EquipmentCategory(id: 'c1', name: 'Enceintes'),
    const EquipmentCategory(id: 'c2', name: 'Micros'),
    const EquipmentCategory(id: 'c3', name: 'Pieds & supports'),
    const EquipmentCategory(id: 'c4', name: 'Table de mixage'),
  ];
  final _items = [
    const EquipmentItem(
        id: 'i1',
        name: 'Enceinte JBL EON 715',
        categoryId: 'c1',
        quantity: 2,
        notes: 'Housses dans la caisse bleue.',
        photoPath: 'enceinte.jpg'),
    const EquipmentItem(
        id: 'i2', name: 'Enceinte de retour Yamaha', categoryId: 'c1', quantity: 1, photoPath: 'enceinte.jpg'),
    const EquipmentItem(
        id: 'i3',
        name: 'Micro Shure SM58',
        categoryId: 'c2',
        quantity: 6,
        notes: 'Un des micros grésille, à vérifier.',
        photoPath: 'micro.jpg'),
    const EquipmentItem(
        id: 'i4',
        name: 'Micro sans fil Sennheiser',
        categoryId: 'c2',
        quantity: 2,
        notes: 'Piles AA.',
        photoPath: 'micro.jpg'),
    const EquipmentItem(id: 'i5', name: 'Pied de micro perche', categoryId: 'c3', quantity: 6, photoPath: 'pied.jpg'),
    const EquipmentItem(id: 'i6', name: 'Table Yamaha MG10XU', categoryId: 'c4', quantity: 1, photoPath: 'table.jpg'),
    const EquipmentItem(id: 'i7', name: 'Rallonge 10 m', quantity: 4),
  ];
  late final _recs = [
    for (final (i, d) in [2, 5, 9, 12, 16, 33].indexed)
      Recording(
        id: 'r$i',
        recordedAt: DateTime.now().subtract(Duration(days: d, hours: 1)),
        audioPath: 'audio.mp3',
        durationSeconds: 5400 + i * 620,
        notes: i.isEven ? '• Hymne à l\'amour : entrée des altos mesure 12\n• Tala al badru : tempo du refrain' : null,
      ),
  ];

  @override
  Future<List<EquipmentCategory>> equipmentCategories() async => [..._cats];
  @override
  Future<EquipmentCategory> addEquipmentCategory(String name) async {
    final c = EquipmentCategory(id: 'c${_cats.length + 1}', name: name);
    _cats.add(c);
    return c;
  }

  @override
  Future<void> renameEquipmentCategory(String id, String name) async {
    final i = _cats.indexWhere((c) => c.id == id);
    _cats[i] = EquipmentCategory(id: id, name: name);
  }

  @override
  Future<void> deleteEquipmentCategory(String id) async => _cats.removeWhere((c) => c.id == id);
  @override
  Future<List<EquipmentItem>> equipment() async => [..._items];
  @override
  Future<void> saveEquipment(
      {String? id,
      required String name,
      String? categoryId,
      required int quantity,
      String? notes,
      String? photoPath}) async {
    final item = EquipmentItem(
        id: id ?? 'i${_items.length + 10}',
        name: name,
        categoryId: categoryId,
        quantity: quantity,
        notes: notes,
        photoPath: photoPath);
    final i = _items.indexWhere((e) => e.id == id);
    i < 0 ? _items.add(item) : _items[i] = item;
  }

  @override
  Future<void> deleteEquipment(EquipmentItem item) async => _items.removeWhere((e) => e.id == item.id);
  @override
  Future<List<Recording>> recordings() async => [..._recs];
  @override
  Future<void> saveRecording(
          {required DateTime recordedAt,
          String? eventId,
          String? title,
          String? notes,
          required String audioPath,
          int? durationSeconds}) async =>
      _recs.insert(
          0,
          Recording(
              id: 'r${_recs.length + 10}',
              recordedAt: recordedAt,
              eventId: eventId,
              title: title,
              notes: notes,
              audioPath: audioPath,
              durationSeconds: durationSeconds));
  @override
  Future<void> updateRecording(String id, {String? title, String? notes}) async {
    final i = _recs.indexWhere((r) => r.id == id);
    final r = _recs[i];
    _recs[i] = Recording(
        id: id,
        recordedAt: r.recordedAt,
        title: title,
        notes: notes,
        audioPath: r.audioPath,
        durationSeconds: r.durationSeconds);
  }

  @override
  Future<void> deleteRecording(Recording r) async => _recs.removeWhere((e) => e.id == r.id);
  @override
  Future<String> upload(String bucket, String fileName, Uint8List bytes, String contentType) async => 'local-$fileName';
  @override
  Future<void> deleteFile(String bucket, String path) async {}
  @override
  Future<String> audioUrl(String path) async => Uri.base.resolve('audio.mp3').toString();
}
