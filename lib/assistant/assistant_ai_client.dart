import '../security/credential_text.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/backend_config.dart';
import '../i18n/app_language.dart';
import '../services/premium_service.dart';
import '../services/ai_professional_context.dart';
import '../services/ai_failure.dart';
import '../services/account_service.dart';
import 'core/skill.dart';

class AiCommandStep {
  const AiCommandStep(this.skillId, this.command, {this.sourceClause});
  final String skillId, command;

  /// Native-only binding; never accepted from model JSON or sent on the wire.
  final String? sourceClause;
}

class AiCommandPlan {
  const AiCommandPlan(this.kind, this.steps, this.message);
  final String kind, message;
  final List<AiCommandStep> steps;
  factory AiCommandPlan.fromJson(Object? value, Set<String> allowed) {
    if (value is! Map ||
        value.length != 3 ||
        !value.keys.toSet().containsAll(['kind', 'steps', 'message'])) {
      throw const FormatException('plan');
    }
    final kind = value['kind'],
        raw = value['steps'],
        message = value['message'];
    if (!const {'execute', 'reply', 'answer', 'clarify', 'unsupported'}
            .contains(kind) ||
        raw is! List ||
        raw.length > 8 ||
        message is! String ||
        message.length > 1000) {
      throw const FormatException('plan');
    }
    final steps = <AiCommandStep>[];
    for (final step in raw) {
      if (step is! Map ||
          step.length != 2 ||
          !step.keys.toSet().containsAll(['skill_id', 'command'])) {
        throw const FormatException('step');
      }
      final id = step['skill_id'], command = step['command'];
      if (id is! String ||
          !allowed.contains(id) ||
          command is! String ||
          command.trim().isEmpty ||
          command.length > 2000 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(command)) {
        throw const FormatException('step');
      }
      steps.add(AiCommandStep(id, command.trim()));
    }
    if (kind == 'execute' && (steps.isEmpty || message.isNotEmpty) ||
        kind == 'reply' && (steps.length != 1 || message.isNotEmpty) ||
        kind != 'execute' && kind != 'reply' && steps.isNotEmpty ||
        const {'clarify', 'unsupported'}.contains(kind) &&
            message.trim().isEmpty) {
      throw const FormatException('plan semantics');
    }
    return AiCommandPlan(
        kind as String, List.unmodifiable(steps), message.trim());
  }
}

/// Only this opt-in visible-input contract enters the model context. Neither
/// route widgets, credentials, database records nor arbitrary state is read.
Map<String, Object?> assistantAiRequest(
    {required String text,
    required AssistantContext context,
    required Iterable<AssistantSkill> skills,
    String? pendingQuestion,
    AskResult? pendingReply,
    List<Map<String, String>> history = const []}) {
  if (containsCredentialValue(text)) {
    throw const FormatException('credential input');
  }
  final catalog = skills.where((s) => s.examples.isNotEmpty).toList();
  if (catalog.isEmpty || catalog.length > 160 || history.length > 6) {
    throw const FormatException('catalog/context size');
  }
  final active = context.modules.activeToolId;
  final modules = context.modules;
  final visible = active != null && modules is FieldModuleContext
      ? (modules as FieldModuleContext).inputFields(active)
      : null;
  final inputs = <String, Object?>{};
  for (final e in (visible ?? const <String, Object?>{}).entries) {
    final v = e.value;
    if (v == null ||
        v is bool ||
        v is String && v.length <= 128 ||
        v is num && v.isFinite) {
      inputs[e.key] = v;
    }
  }
  return {
    'version': 1,
    'text': text,
    'lang': context.lang.name,
    'capabilities': [
      for (final s in catalog)
        {
          'id': s.id,
          'tool_id': s.toolId,
          'tier': s.tier.name,
          'read_only': s.readOnly,
          'safety_critical': s.safetyCritical,
          if (s.professionalProfileFields.isNotEmpty)
            'professional_profile_fields':
                s.professionalProfileFields.map((f) => f.name).toList(),
          if (s.actionScope case final scope?)
            'action_scope': {
              'tool_ids': scope.toolIds,
              'actions': scope.actions
                  .map((key, target) => MapEntry(key, target.wireName)),
            },
          'examples': s.examples
              .take(3)
              .map((e) => context.lang == AppLanguage.pl ? e.pl : e.en)
              .toList(),
        }
    ],
    'context': {
      'active_tool': active,
      'inputs': inputs,
      'pending_question': pendingQuestion,
      if (pendingReply != null)
        'pending_reply': {
          'skill_id': pendingReply.partial.skill.id,
          'slot': pendingReply.slot,
          'choices': [
            for (final choice in pendingReply.choices.take(6))
              choice.utterance.length <= 128
                  ? choice.utterance
                  : choice.utterance.substring(0, 128)
          ]
        },
      'history': [
        for (final item in history)
          {...item, 'text': redactCredentialText(item['text'] ?? '')}
      ]
    },
  };
}

class AssistantAiUnavailable implements Exception {
  const AssistantAiUnavailable(this.status, {this.code});
  final int? status;
  final String? code;
  AiFailure get failure => AiFailure(status, code: code);
}

class AssistantAiClient {
  AssistantAiClient(
      {http.Client? client, Future<Map<String, String>> Function()? identity})
      : _client = client ?? http.Client(),
        _identity = identity ?? PremiumService.instance.authHeaders;
  final http.Client _client;
  final Future<Map<String, String>> Function() _identity;
  Future<AiCommandPlan> interpret(Map<String, Object?> request) async {
    final text = request['text'];
    if (text is String && containsCredentialValue(text)) {
      throw const AssistantAiUnavailable(null, code: 'AI_SENSITIVE_INPUT');
    }
    final context = request['context'];
    final safeRequest = {...request};
    if (context is Map && context['history'] is List) {
      safeRequest['context'] = {
        ...context,
        'history': [
          for (final item in context['history'] as List)
            if (item is Map && item['text'] is String)
              {...item, 'text': redactCredentialText(item['text'] as String)}
            else
              item
        ]
      };
    }
    final catalog = request['capabilities'] as List;
    final allowed = {for (final c in catalog) (c as Map)['id'] as String};
    try {
      final identity = await _identity();
      final profile = await AiProfessionalContext.instance.capture();
      final response = await _client
          .post(Uri.parse('${BackendConfig.baseUrl}/api/fitter/ai/assistant'),
              headers: {
                'Content-Type': 'application/json',
                ...identity,
                ...profile.headers,
              },
              body: jsonEncode({...safeRequest, ...profile.body}))
          .timeout(const Duration(seconds: 30));
      profile.requireCurrent();
      if (response.statusCode != 200) {
        throw AssistantAiUnavailable(response.statusCode,
            code: AiFailure.fromHttp(response.statusCode, response.bodyBytes)
                .code);
      }
      return AiCommandPlan.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)), allowed);
    } on AssistantAiUnavailable {
      rethrow;
    } on FormatException {
      throw const AssistantAiUnavailable(200, code: 'AI_PLAN_INVALID');
    } on AccountException {
      throw const AssistantAiUnavailable(null, code: 'AI_CONTEXT_CHANGED');
    } catch (_) {
      throw const AssistantAiUnavailable(null);
    }
  }

  void close() => _client.close();
}
