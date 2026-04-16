import 'dart:async';

import 'local_repo.dart';
import 'param_signature.dart';

class WelderPipeCommunitySyncService {
  final _repo = WelderPipeLocalRepo();

  Future<void> submitMyParamToCommunity(Map<String, dynamic> payload) async {
    final sig = WelderPipeSignature.signature(payload);
    await _repo.enqueueCommunitySubmission(signature: sig, payload: payload);
  }

  Future<void> syncOutboxOnce() async {
    final pending = await _repo.listPendingOutbox(limit: 20);
    if (pending.isEmpty) return;
    for (final row in pending) {
      final id = row['id'] as int;
      await _repo.markOutboxSent(id);
    }
  }
}
