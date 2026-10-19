import '../../i18n/app_language.dart';

/// Tekst asystenta w obu językach. Umiejętności nie znają `BuildContext`,
/// więc nie używają `context.tr` — język wybiera sesja przy wyświetlaniu.
class AssistantText {
  const AssistantText(this.pl, this.en);

  /// Ten sam tekst w obu językach (kody, nazwy własne: „DN ↔ mm", „Sch 40").
  const AssistantText.same(String text)
      : pl = text,
        en = text;

  final String pl, en;

  String of(AppLanguage l) => l == AppLanguage.en ? en : pl;

  @override
  bool operator ==(Object other) =>
      other is AssistantText && other.pl == pl && other.en == en;

  @override
  int get hashCode => Object.hash(pl, en);

  @override
  String toString() => 'AssistantText($pl | $en)';
}
