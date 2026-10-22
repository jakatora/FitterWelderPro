import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app_navigator.dart';
import '../../i18n/app_language.dart';
import '../../screens/ai_chat_screen.dart';
import '../core/assistant_panel_controller.dart';
import '../assistant_history.dart';

/// Independent Overlay supplies text selection and tooltips above Navigator.
/// It does not intercept the uncovered drawing area.
class AssistantOverlay extends StatefulWidget {
  const AssistantOverlay({super.key, required this.child, this.assistant});
  final Widget child;
  final Widget? assistant;
  @override
  State<AssistantOverlay> createState() => _AssistantOverlayState();
}

class _AssistantOverlayState extends State<AssistantOverlay> {
  late final _entry = OverlayEntry(builder: _buildPanel);
  final _controller = AssistantPanelController.instance;
  final _popEntry = _PanelPopEntry();
  ModalRoute<dynamic>? _route;
  @override
  void initState() {
    super.initState();
    appRoutes.addListener(_refresh);
    _controller.addListener(_refresh);
  }

  void _refresh() {
    if (!mounted) return;
    if (appRoutes.assistantPresentation && !_controller.expanded) {
      // Back from a calculator can return to the dedicated conversation page
      // after the compact panel was collapsed. Never expose an empty page.
      _controller.setExpanded(true);
      return;
    }
    final top = appRoutes.top;
    final route = top is ModalRoute<dynamic> ? top : null;
    if (!identical(route, _route)) {
      _route?.unregisterPopEntry(_popEntry);
      _route = route;
      _route?.registerPopEntry(_popEntry);
    }
    _popEntry.canPopNotifier.value = appRoutes.assistantPresentation ||
        !_controller.expanded ||
        !appRoutes.assistantAvailable;
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _route?.unregisterPopEntry(_popEntry);
    _popEntry.canPopNotifier.dispose();
    appRoutes.removeListener(_refresh);
    _controller.removeListener(_refresh);
    super.dispose();
  }

  Widget _buildPanel(BuildContext context) {
    final visible = appRoutes.assistantAvailable;
    final expanded = _controller.expanded;
    final fullPage = appRoutes.assistantPresentation;
    final media = MediaQuery.of(context);
    return Positioned(
      left: 8,
      right: 8,
      bottom: math.max(media.viewInsets.bottom, media.padding.bottom) + 12,
      child: Offstage(
        offstage: !visible,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Offstage(
                offstage: expanded,
                child: SizedBox.square(
                    dimension: 64,
                    child: FloatingActionButton(
                      heroTag: 'global-assistant',
                      tooltip: context.tr(
                          pl: 'Powiedz, co zrobić', en: 'Tell me what to do'),
                      onPressed: () => _controller.setExpanded(true),
                      child: const Icon(Icons.record_voice_over),
                    ))),
            Offstage(
                offstage: !expanded,
                child: SizedBox(
                  height: fullPage
                      ? math.max(
                          0,
                          media.size.height -
                              math.max(media.viewInsets.bottom,
                                  media.padding.bottom) -
                              media.padding.top -
                              24)
                      : math.min(
                          media.size.height * .4,
                          math.max(
                              180,
                              media.size.height -
                                  media.viewInsets.bottom -
                                  100)),
                  child: Material(
                    elevation: 12,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: [
                      SizedBox(
                          height: 48,
                          child: Row(children: [
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(context.tr(
                                    pl: 'Asystent', en: 'Assistant'))),
                            ListenableBuilder(
                                listenable: AssistantHistoryStore.instance,
                                builder: (context, _) {
                                  final history =
                                      AssistantHistoryStore.instance;
                                  return IconButton(
                                      tooltip: context.tr(
                                          pl: 'Czytaj odpowiedzi na głos',
                                          en: 'Read replies aloud'),
                                      icon: Icon(history.speakReplies
                                          ? Icons.volume_up
                                          : Icons.volume_off),
                                      onPressed: () => history.setSpeakReplies(
                                          !history.speakReplies));
                                }),
                            IconButton(
                                tooltip: context.tr(pl: 'Zwiń', en: 'Collapse'),
                                onPressed: () {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  if (appRoutes.assistantPresentation) {
                                    appNavigatorKey.currentState?.pop();
                                  }
                                  _controller.setExpanded(false);
                                },
                                icon: const Icon(Icons.keyboard_arrow_down)),
                          ])),
                      Expanded(
                          child: widget.assistant ??
                              const AiChatScreen(embedded: true)),
                    ]),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        Positioned.fill(child: Overlay(initialEntries: [_entry])),
      ]);
}

class _PanelPopEntry extends PopEntry<dynamic> {
  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier<bool>(true);
  @override
  void onPopInvokedWithResult(bool didPop, dynamic result) {
    if (!didPop &&
        appRoutes.assistantAvailable &&
        AssistantPanelController.instance.expanded) {
      FocusManager.instance.primaryFocus?.unfocus();
      AssistantPanelController.instance.setExpanded(false);
    }
  }
}
