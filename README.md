# Appli GDC

Application du Groupe de Chant Narbonne (GDC) :

- **Chants** : paroles en PDF, YouTube, audio, note de départ enregistrée ; livrets PDF générés
  avec sommaire et parties ; mode concert (pages préparées d'avance, note du chant en cours).
- **Agenda** : répétitions et prestations, réponses de présence, appel, historique des prestations,
  matériel à emporter et tenue du jour.
- **Répètes** : diapason, métronome, enregistrement des répétitions (avec repères par chant),
  import de fichiers audio.
- **Inventaire** : matériel du local, tenues et vêtements, avec photos.
- **Annonces, tâches et notifications** sur le téléphone.
- **Membres** : rôles, sauvegarde complète et jauge de stockage (admins).

L'appli marche hors connexion pour tout ce qui est déjà ouvert une fois.

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
- **Admin** : gère les membres et leurs rôles, sauvegarde et restaure.
- **Responsable** : écrit les annonces et confie les tâches (avec l'admin).
- **Référents** (Chant Français, Chant Arabe, Sono, Artistique, Douf) : ajoutent et modifient
  chants, livrets, agenda, inventaire, tenues et enregistrements (comme l'admin et le responsable).
- **Membres** : consultent, écoutent et répondent aux événements et à leurs tâches.

## Supabase

Projet `Appli GDC` (région Paris, offre gratuite : 1 Go de fichiers). Le schéma est dans
`supabase/migrations/`, les notifications dans `supabase/functions/notifications`.
Les fichiers sont dans des espaces privés : `lyrics` (PDF), `audio`, `booklets`,
`enregistrements` (répétitions et notes) et `materiel` (photos).

## Tests

```bash
flutter analyze lib test
flutter test   # génère aussi build/test_booklet.pdf à partir de test/fixtures
```

## Licences

- Polices Amiri, Poppins et DM Serif Display : SIL Open Font License (`assets/fonts/OFL-*.txt`).
- Syncfusion (PDF et lecteur PDF) : licence communautaire gratuite pour les
  associations et petites structures.
