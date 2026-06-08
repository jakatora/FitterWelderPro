import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../i18n/app_language.dart';
import '../services/backend_service.dart';

class TutorScreen extends StatefulWidget {
  const TutorScreen({super.key});

  @override
  State<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends State<TutorScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<_Message> _messages = [];

  /// P0-10: monotonic request counter. Increment on every send; only the
  /// response that matches the current counter is allowed to render. A
  /// late answer to question A no longer appears under question B
  /// (which would have the welder applying the wrong undercut/preheat
  /// limit — joint fails NDT or service).
  int _requestSeq = 0;

  /// P0-10: pre-normalised scope dictionary. Covers the actual code
  /// keywords welders type when asking the tutor (WPS / WPQR / PQR / HAZ /
  /// PWHT / NDT / RT / UT / PT / VT / process codes + standards prefixes).
  /// Without these the scope filter rejects the exact questions the tutor
  /// exists for and the user always sees "out_of_scope" → "no_answer".
  static const List<String> _kScopeKeywords = [
    'spaw', 'weld', 'mont', 'fit', 'assemble',
    'wps', 'wpqr', 'pqr', 'haz', 'pwht', 'preheat',
    'ndt', ' rt ', ' ut ', ' pt ', ' vt ', 'rentgen', 'penetrant',
    'gtaw', 'gmaw', 'smaw', 'fcaw', 'saw', 'tig', 'mig', 'mag',
    'iso', 'asme', 'aws', ' en ', 'pn-en', 'din',
    'b31', 'd1.1', '5817', '9606', '15614', '9692', '13920', 'ped',
    'rura', 'rurociag', 'spoina', 'orbital',
    'pipe', 'pipeline', 'joint', 'pass', 'bead', 'tube',
  ];

  /// Strips PL/EN diacritics so "świszczen" / "łuk" / etc. still match
  /// ASCII scope keywords. Best-effort — covers PL + DE/CS extras.
  String _ascii(String input) {
    const map = {
      'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n',
      'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z',
      'ä': 'a', 'ö': 'o', 'ü': 'u', 'ß': 'ss',
      'á': 'a', 'é': 'e', 'í': 'i', 'ú': 'u',
    };
    final buf = StringBuffer();
    for (final ch in input.toLowerCase().runes) {
      final s = String.fromCharCode(ch);
      buf.write(map[s] ?? s);
    }
    return buf.toString();
  }

  @override
  void initState() {
    super.initState();
    // Drives PopScope.canPop so back-nav prompt appears the moment user types.
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
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

    // P0-10: diacritic-insensitive scope match against the widened keyword
    // dictionary. The old 5-word filter rejected every actual code question
    // a welder types ("WPQR dla P91?" → out-of-scope).
    final normalised = _ascii(text);
    final isInScope = _kScopeKeywords.any(normalised.contains);
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
    final mySeq = ++_requestSeq;

    // Attempt to retrieve or search for an answer asynchronously. The 20 s
    // timeout guards against a backend that takes forever (frozen Render
    // cold-start, basement-signal stall); _requestSeq ensures only the
    // response to the LATEST question renders — a stale late answer to a
    // prior question would otherwise display under the wrong prompt.
    BackendService.getOrSearchAnswer(text)
        .timeout(const Duration(seconds: 20))
        .then((answer) {
      if (!mounted || mySeq != _requestSeq) return;
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
    }).catchError((_) {
      if (!mounted || mySeq != _requestSeq) return;
      // Network drop / backend 500: clear the "searching..." bubble and
      // surface a Retry — on a noisy shop floor a frozen screen is the worst UX.
      setState(() {
        if (searchIndex >= 0 && searchIndex < _messages.length) {
          _messages.removeAt(searchIndex);
        }
      });
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.tr(
            pl: 'Brak połączenia z tutorem. Sprawdź sieć.',
            en: 'Cannot reach tutor. Check your connection.',
          )),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: context.tr(pl: 'Ponów', en: 'Retry'),
            onPressed: () {
              if (!mounted) return;
              _controller.text = text;
              _sendMessage();
            },
          ),
        ),
      );
    });
  }

  // Confirms discarding a half-typed question — gloves + bumpy site swipes
  // make accidental back-nav easy, and losing a long welding query is painful.
  Future<bool> _confirmDiscardPending() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr(
          pl: 'Porzucić wpisane pytanie?',
          en: 'Discard typed question?',
        )),
        content: Text(context.tr(
          pl: 'Twój tekst zostanie utracony.',
          en: 'Your text will be lost.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr(pl: 'Wróć', en: 'Keep editing')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr(pl: 'Porzuć', en: 'Discard')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _controller.text.trim().isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final discard = await _confirmDiscardPending();
        if (discard && mounted) nav.pop();
      },
      child: Scaffold(
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
    ),
    );
  }
}

class _Message {
  final String text;
  final bool isUser;
  _Message({required this.text, required this.isUser});
}