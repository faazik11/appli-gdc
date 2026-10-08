import 'dart:js_interop';

@JS('gdcStandalone')
external bool? get _standalone;

@JS('gdcIos')
external bool? get _ios;

/// Vrai quand la page est ouverte depuis l'icône de l'écran d'accueil.
bool get isInstalledApp => _standalone ?? false;
bool get isIos => _ios ?? false;
