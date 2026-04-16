/// Represents an authenticated user of the application.
///
/// This model stores basic information about a logged in user. It is kept
/// deliberately simple since this example does not persist users to a
/// remote backend. In a real application you might store additional
/// metadata such as an ID token or roles.
class User {
  /// The user's email address.
  final String email;

  /// The user's display name. If null it should default to the portion of
  /// the email before the '@' sign.
  final String displayName;

  /// An optional URL pointing to the user's profile image. This is used
  /// when logging in with Google.
  final String? photoUrl;

  User({
    required this.email,
    required this.displayName,
    this.photoUrl,
  });

  /// Creates a [User] instance from a Google account. If the account does not
  /// have a display name then the email prefix will be used instead.
  factory User.fromGoogleAccount(dynamic account) {
    final email = account.email as String;
    final displayName = (account.displayName as String?) ?? email.split('@').first;
    final photoUrl = account.photoUrl as String?;
    return User(email: email, displayName: displayName, photoUrl: photoUrl);
  }
}