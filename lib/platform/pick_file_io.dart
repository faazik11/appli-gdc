import 'package:file_picker/file_picker.dart';

/// Ouvre le sélecteur de fichiers du téléphone ; null si rien n'est choisi.
Future<PlatformFile?> pickOneFile({FileType type = FileType.any, List<String>? extensions}) =>
    FilePicker.pickFile(type: type, allowedExtensions: extensions);
