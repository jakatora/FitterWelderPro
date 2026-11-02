/// A Windows database location cannot be selected without the user's help.
class DatabaseLocationProblem implements Exception {
  const DatabaseLocationProblem(
      {required this.candidates, this.missing, this.reason});

  final List<String> candidates;
  final String? missing;
  final String? reason;

  @override
  String toString() => missing == null
      ? 'Multiple existing databases: ${candidates.join(' | ')}'
      : 'The previously selected database is unavailable: $missing';
}
