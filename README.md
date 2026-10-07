# Appli GDC

Application de la chorale GDC : bibliothèque de chants (PDF de paroles, YouTube, audio),
écran de répétition et générateur de livrets PDF avec sommaire et parties.

Flutter (Android, iOS, web) + Supabase (base de données, fichiers, comptes).

## Lancer l'appli

```bash
flutter pub get
flutter run                 # téléphone ou émulateur branché
flutter run -d chrome       # version web
flutter build apk --release # fichier .apk à installer sur Android
flutter build web --no-web-resources-cdn
```

## Version web en ligne

Chaque envoi sur la branche `main` reconstruit et publie automatiquement la version web
sur GitHub Pages (voir `.github/workflows/deploy-web.yml`) :
https://faazik11.github.io/appli-gdc/

## Comptes et rôles

- Le **premier compte créé** devient automatiquement **admin**.
- Les comptes suivants sont **en attente** : l'admin les valide depuis l'écran *Membres*.
- **Admin** et **Chef de chœur** ajoutent/modifient les chants et les livrets ;
  les **Membres** consultent et écoutent.

## Supabase

Projet `Appli GDC` (région Paris). Le schéma est dans `supabase/migrations/`.
Les fichiers sont dans trois espaces privés : `lyrics` (PDF), `audio`, `booklets`.

## Tests

```bash
flutter test   # génère build/test_booklet.pdf à partir de test/fixtures
```

## Licences

- Police Amiri : SIL Open Font License (`assets/fonts/OFL.txt`).
- Syncfusion (PDF et lecteur PDF) : licence communautaire gratuite pour les
  associations et petites structures.
