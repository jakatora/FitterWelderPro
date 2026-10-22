import 'dart:async';
import 'package:flutter/material.dart';
import '../../app_navigator.dart';
import '../../widgets/tool_registry.dart';
import 'skill.dart';

abstract interface class RecordToolHandle {
  String? get selectedRecordId;
}

/// Explicit native read ports only. Credential forms expose no inputs.
abstract interface class InputToolHandle {
  Map<String, Object?> get inputFields;
}

/// Only explicitly implemented native actions can be invoked; no widget search
/// or arbitrary field/text copying is exposed.
abstract interface class ModuleActionHandle {
  Future<ModuleActionResult> performAction(String action, {String? field});
}

abstract class ToolHandle {
  String get toolId;
  Set<String> get supportedFields;
  Future<Set<String>> apply(Map<String, Object?> fields);
}

/// One route may contain several calculators. Only its selected tab is active.
abstract class TabbedToolHandle implements ToolHandle {
  Set<String> get toolIds;
  bool selectTool(String toolId);
}

class _HandleEntry {
  _HandleEntry(this.route, this.ready);
  final Route<dynamic>? route;
  bool ready;
}

class _Waiter {
  _Waiter(this.toolId);
  final String toolId;
  final completer = Completer<ToolHandle?>();
}

/// Handles belong to route instances, not tool IDs: hidden copies never
/// receive a command intended for the visible screen.
class ToolBridge
    implements
        ModuleContext,
        RecordModuleContext,
        FieldModuleContext,
        ModuleActionContext {
  @override
  Future<ModuleActionResult> performModuleAction(String toolId, String action,
      {String? field}) async {
    final handle = current;
    if (handle == null ||
        handle.toolId != toolId ||
        handle is! ModuleActionHandle ||
        !isReady(handle) ||
        appRoutes.top is PopupRoute) {
      return const ModuleActionResult(
          false,
          AssistantText(
              'Otwórz właściwy moduł i zamknij okno dialogowe, zanim wykonasz tę czynność.',
              'Open the matching module and close any dialog before performing this action.'));
    }
    try {
      return await (handle as ModuleActionHandle)
          .performAction(action, field: field);
    } catch (_) {
      return const ModuleActionResult(
          false,
          AssistantText(
              'Nie udało się wykonać tej czynności. Spróbuj ponownie.',
              'The action could not be completed. Please try again.'));
    }
  }

  @override
  Map<String, Object?>? inputFields(String toolId) {
    final handle = current;
    if (handle == null ||
        handle.toolId != toolId ||
        handle is! InputToolHandle ||
        !isReady(handle) ||
        appRoutes.top is PopupRoute) {
      return null;
    }
    return (handle as InputToolHandle).inputFields;
  }

  @override
  String? selectedRecordId(String toolId) {
    final handle = current;
    return handle?.toolId == toolId && handle is RecordToolHandle
        ? (handle as RecordToolHandle).selectedRecordId
        : null;
  }

  ToolBridge() {
    appRoutes.addListener(_completeWaiters);
  }
  static ToolBridge _instance = ToolBridge();
  static ToolBridge get instance => _instance;
  final _handles = <ToolHandle, _HandleEntry>{};
  final _waiters = <_Waiter>[];

  @visibleForTesting
  static void reset() {
    appRoutes.removeListener(_instance._completeWaiters);
    for (final w in _instance._waiters) {
      if (!w.completer.isCompleted) w.completer.complete(null);
    }
    _instance = ToolBridge();
  }

  void attach(ToolHandle handle,
      {required Route<dynamic>? route, bool ready = false}) {
    _handles[handle] = _HandleEntry(route, ready);
    _completeWaiters();
  }

  void detach(ToolHandle handle) => _handles.remove(handle);
  void markReady(ToolHandle handle) {
    _handles[handle]?.ready = true;
    _completeWaiters();
  }

  ToolHandle? get current {
    for (final entry in _handles.entries) {
      if (entry.value.route?.isCurrent == true) return entry.key;
    }
    return null;
  }

  bool isReady(ToolHandle h) => _handles[h]?.ready ?? false;
  @override
  String? get activeToolId => current?.toolId ?? appRoutes.toolId;
  @override
  bool get onHomeOrAssistant =>
      appRoutes.top?.isFirst == true || appRoutes.toolId == 'assistant';

  void _completeWaiters() {
    if (appRoutes.top is PopupRoute) {
      for (final w in List<_Waiter>.from(_waiters)) {
        _waiters.remove(w);
        if (!w.completer.isCompleted) w.completer.complete(null);
      }
      return;
    }
    final handle = current;
    if (handle == null || !isReady(handle)) return;
    for (final w in List<_Waiter>.from(_waiters)) {
      if (w.toolId == handle.toolId && !w.completer.isCompleted) {
        _waiters.remove(w);
        w.completer.complete(handle);
      }
    }
  }

  Future<ToolHandle?> whenReady(String toolId,
      {Duration timeout = const Duration(seconds: 3)}) async {
    final h = current;
    if (h?.toolId == toolId && isReady(h!)) return h;
    final waiter = _Waiter(toolId);
    _waiters.add(waiter);
    final timer = Timer(timeout, () {
      if (!waiter.completer.isCompleted) waiter.completer.complete(null);
    });
    try {
      return await waiter.completer.future;
    } finally {
      timer.cancel();
      _waiters.remove(waiter);
    }
  }
}

mixin ToolHandleHost<T extends StatefulWidget> on State<T>
    implements ToolHandle {
  bool _ready = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ToolBridge.instance
        .attach(this, route: ModalRoute.of(context), ready: _ready);
  }

  void markReady() {
    _ready = true;
    if (mounted) ToolBridge.instance.markReady(this);
  }

  @override
  void dispose() {
    ToolBridge.instance.detach(this);
    super.dispose();
  }
}

enum ShowOutcome {
  appliedInPlace,
  opened,
  replaced,
  offeredChip,
  blockedByPopup,
  timedOut,
  unsupportedFields,
  unavailable
}

/// Apply in place, replace a previous read-only pilot, or offer a chip.
/// Explicit requests may navigate; an unrelated calculation never hijacks
/// a user-opened screen or a dialog.
Future<ShowOutcome> showInModule(ShowInModule show,
    {bool explicit = false,
    Duration timeout = const Duration(seconds: 3)}) async {
  final bridge = ToolBridge.instance;
  final top = appRoutes.top;
  if (top is PopupRoute) return ShowOutcome.blockedByPopup;
  var same = bridge.activeToolId == show.toolId;
  final container = bridge.current;
  if (!same &&
      container is TabbedToolHandle &&
      container.toolIds.contains(show.toolId)) {
    if (!explicit && !bridge.onHomeOrAssistant) return ShowOutcome.offeredChip;
    same = container.selectTool(show.toolId);
  }
  var outcome = ShowOutcome.appliedInPlace;
  if (!same) {
    const transientTools = {'dn_mm', 'wall_thickness', 'heat_input'};
    final replace = top?.settings.arguments == kAssistantRouteOrigin &&
        transientTools.contains(appRoutes.toolId);
    if (!explicit && !bridge.onHomeOrAssistant && !replace) {
      return ShowOutcome.offeredChip;
    }
    final tool = toolById(show.toolId);
    final context = appNavigatorKey.currentState?.overlay?.context;
    if (context == null) return ShowOutcome.unavailable;
    if (tool == null) {
      // Navigation entries own their existing consent gates. They accept no
      // field injection; account credentials stay in the dedicated form.
      final entry = kNavEntries
          .where((e) => e.id == show.toolId && e.available)
          .firstOrNull;
      if (entry == null || show.fields.isNotEmpty) {
        return ShowOutcome.unavailable;
      }
      unawaited(entry.open(context));
      return ShowOutcome.opened;
    }
    unawaited(openTool(context, tool, byAssistant: true, replace: replace));
    outcome = replace ? ShowOutcome.replaced : ShowOutcome.opened;
  }
  if (show.fields.isEmpty) return outcome;
  final handle = await bridge.whenReady(show.toolId, timeout: timeout);
  if (handle == null) {
    return appRoutes.top is PopupRoute
        ? ShowOutcome.blockedByPopup
        : ShowOutcome.timedOut;
  }
  // Another route may have appeared while preferences were loading.
  if (appRoutes.top is PopupRoute) return ShowOutcome.blockedByPopup;
  if (!identical(bridge.current, handle)) return ShowOutcome.offeredChip;
  final unsupported =
      show.fields.keys.toSet().difference(handle.supportedFields);
  if (unsupported.isNotEmpty) return ShowOutcome.unsupportedFields;
  final rejected = await handle.apply(show.fields);
  return rejected.isEmpty ? outcome : ShowOutcome.unsupportedFields;
}
