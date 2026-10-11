import 'package:file_picker/file_picker.dart';
import 'package:file_picker_web/file_picker_web.dart';

/// Ouvre le sélecteur de fichiers du téléphone ; null si rien n'est choisi.
///
/// Sur iPhone, la fenêtre de l'appli reprend la main avant que le fichier soit transmis
/// (copie depuis Fichiers ou iCloud). Par défaut, le sélecteur prend ça pour une annulation
/// au bout d'une demi-seconde : on attend donc le vrai choix (ou l'annulation) du navigateur.
Future<PlatformFile?> pickOneFile({FileType type = FileType.any, List<String>? extensions}) => FilePicker.pickFile(
      type: type,
      allowedExtensions: extensions,
      webOptions: const FilePickerWebOptions(cancelUploadOnWindowBlur: false),
    );
