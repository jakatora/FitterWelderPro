import '../services/account_service.dart';

/// Captures identity before async I/O, so a late operation cannot follow a
/// different user. Legacy device data belongs to the offline guest.
class LocalRecordOwner {
  LocalRecordOwner._(this.key, this._account, this._revision);
  static const guest = 'guest';
  final String key;
  final AccountService _account;
  final int _revision;

  static Future<LocalRecordOwner> capture() async {
    final account = AccountService.instance;
    final revision = account.sessionRevision;
    await account.load();
    if (!identical(account, AccountService.instance) ||
        revision != account.sessionRevision) {
      throw AccountException(
          'Sesja zmieniła się. Spróbuj ponownie. / Session changed. Please try again.');
    }
    if (account.needsIdentityRefresh && account.localOwnerId == null) {
      throw AccountException(
          'Otwórz konto i ponów odczyt profilu. / Open your account and retry loading the profile.');
    }
    final id = account.account?['id'] ?? account.localOwnerId;
    if (account.account != null && (id is! String || id.isEmpty)) {
      throw AccountException(
          'Nie udało się ustalić właściciela danych. / Could not identify the data owner.');
    }
    return LocalRecordOwner._(
        id is String ? 'account:$id' : guest, account, account.sessionRevision);
  }

  void requireCurrent() {
    if (!identical(_account, AccountService.instance) ||
        _revision != _account.sessionRevision) {
      throw AccountException(
          'Sesja zmieniła się. Spróbuj ponownie. / Session changed. Please try again.');
    }
  }
}
