/// Font choices offered in Settings. Every family is bundled in
/// assets/fonts (see pubspec.yaml `fonts:`), so switching works offline and
/// each weight renders as a real face.
///
/// The description shown under each name is translated in the Settings
/// screen (`_fontDescription`); the names themselves are proper nouns.
enum AppFont {
  poppins('Poppins', 'Poppins'),
  inter('Inter', 'Inter'),
  roboto('Roboto', 'Roboto'),
  openSans('Open Sans', 'OpenSans'),
  nunito('Nunito', 'Nunito'),
  atkinson('Atkinson Hyperlegible', 'AtkinsonHyperlegible'),
  merriweather('Merriweather', 'Merriweather');

  const AppFont(this.label, this.fontFamily);

  final String label;
  final String fontFamily;

  /// Poppins has always been the AlmaWorks typeface.
  static const AppFont fallback = AppFont.poppins;

  static AppFont fromName(String? name) =>
      AppFont.values.firstWhere((f) => f.name == name, orElse: () => fallback);
}
