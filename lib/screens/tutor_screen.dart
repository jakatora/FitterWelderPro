import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/backend_service.dart';

class TutorScreen extends StatefulWidget {
  const TutorScreen({super.key});

  @override
  State<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends State<TutorScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<_Message> _messages = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Sends the current text from the input field to the message list
  /// and triggers a simulated tutor response.
  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_Message(text: text, isUser: true));
    });
    _controller.clear();

    final lower = text.toLowerCase();
    final isInScope = lower.contains('spaw') ||
        lower.contains('weld') ||
        lower.contains('mont') ||
        lower.contains('fit') ||
        lower.contains('assemble');
    if (!isInScope) {
      setState(() {
        _messages.add(_Message(
          text: AppLocalizations.of(context).translate('tutor_out_of_scope'),
          isUser: false,
        ));
      });
      return;
    }
    setState(() {
      _messages.add(_Message(
        text: AppLocalizations.of(context).translate('tutor_searching'),
        isUser: false,
      ));
    });
    final searchIndex = _messages.length - 1;

    // Attempt to retrieve or search for an answer asynchronously.
    BackendService.getOrSearchAnswer(text).then((answer) {
      if (!mounted) return;
      setState(() {
        if (searchIndex >= 0 && searchIndex < _messages.length) {
          _messages.removeAt(searchIndex);
        }
        if (answer != null && answer.isNotEmpty) {
          _messages.add(_Message(text: answer, isUser: false));
        } else {
          _messages.add(_Message(
            text: AppLocalizations.of(context).translate('tutor_no_answer'),
            isUser: false,
          ));
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).translate('tutor_menu_appbar')),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              reverse: true,
              itemBuilder: (context, index) {
                final message = _messages[_messages.length - 1 - index];
                return Align(
                  alignment:
                      message.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: message.isUser
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      message.text,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context)
                          .translate('tutor_input_hint'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _sendMessage,
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Message {
  final String text;
  final bool isUser;
  _Message({required this.text, required this.isUser});
}