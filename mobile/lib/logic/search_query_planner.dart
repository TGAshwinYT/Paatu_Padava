/// Decides what query text is actually searched for each kind of tap.
///
/// BUG THIS FIXES: tapping a recent search / trending-artist chip used to go
/// through the *browse-category* handler, which prepends the preferred language
/// ("Tamil ") to the text. The search box then showed "Tamil Believer", it was
/// saved back into history, and the strict language filter hid every
/// non-Tamil result.
class SearchQueryPlanner {
  SearchQueryPlanner._();

  /// Recent searches, trending-artist chips and typed text: searched EXACTLY as written.
  static String forExactQuery(String query) => query.trim();

  /// Browse-category tiles ("Workout", "Party"): add the user's preferred
  /// language only when the query does not already name a language.
  static String forCategory(
    String query, {
    required String preferredLanguage,
    String? explicitLanguage,
  }) {
    final clean = query.trim();
    final pref = preferredLanguage.trim();
    if (pref.isEmpty) return clean;
    if (explicitLanguage != null) return clean;
    if (clean.toLowerCase().contains(pref.toLowerCase())) return clean;
    return '$pref $clean';
  }
}
