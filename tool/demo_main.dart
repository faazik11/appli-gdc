// Démo hors ligne pour les captures d'écran : `flutter build web -t tool/demo_main.dart`
// puis ouvrir index.html?screen=home|songs|booklets|members|login&theme=dark
import 'package:appli_gdc/models.dart';
import 'package:appli_gdc/screens/auth_screen.dart';
import 'package:appli_gdc/screens/home_screen.dart';
import 'package:appli_gdc/screens/members_screen.dart';
import 'package:appli_gdc/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

const _categories = [
  Category(id: 1, name: 'Chants Français'),
  Category(id: 2, name: 'Chants Arabe'),
  Category(id: 3, name: 'Chants Mariage'),
  Category(id: 4, name: 'Chants International'),
  Category(id: 5, name: 'Livrets'),
];

final _now = DateTime.now();
Song _song(String id, String title, int cat, {bool pdf = true, bool yt = false, bool audio = false, List<String> tags = const [], int ago = 1}) =>
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
  await initializeDateFormatting('fr_FR');
  final q = Uri.base.queryParameters;
  final screen = q['screen'] ?? 'home';
  final tab = const {'home': 0, 'songs': 1, 'booklets': 2, 'members': 3}[screen] ?? 0;
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('fr', 'FR'),
    supportedLocales: const [Locale('fr', 'FR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    themeMode: q['theme'] == 'dark' ? ThemeMode.dark : ThemeMode.light,
    home: screen == 'login'
        ? const AuthScreen()
        : HomeScreen(
            profile: _profiles.first,
            initialTab: tab,
            load: () async => LibraryData(_categories, _songs, _booklets),
            membersPanel: MembersPanel(load: () async => _profiles, setRole: (_, __) async {}),
          ),
  ));
}
