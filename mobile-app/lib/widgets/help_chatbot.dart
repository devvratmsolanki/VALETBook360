import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../state/providers.dart';
import '../theme/v_colors.dart';
import '../theme/v_theme.dart';
import '../theme/v_tokens.dart';

/// Floating, role-aware help assistant for the Flutter app. Designed to be the
/// top layer of a Stack (it positions its own launcher + panel), mounted once
/// in [main] above the router and gated on auth — so it appears on every
/// authenticated screen and never on login. The Groq API key stays server-side
/// (the auth-service /assistant/chat endpoint); this only sends/receives text.
class HelpChatbot extends ConsumerStatefulWidget {
  const HelpChatbot({super.key});

  @override
  ConsumerState<HelpChatbot> createState() => _HelpChatbotState();
}

class _HelpChatbotState extends ConsumerState<HelpChatbot> {
  bool _open = false;
  bool _busy = false;
  String? _error;
  final _messages = <({String role, String content})>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();

  static const _suggestions = [
    'How do I check in a car?',
    'How do key slots work?',
    'How do I add a driver?',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    final history = [
      for (final m in _messages) {'role': m.role, 'content': m.content},
    ];
    setState(() {
      _messages.add((role: 'user', content: text));
      _capMessages();
      _input.clear();
      _busy = true;
      _error = null;
    });
    _scrollToEnd();
    try {
      final reply = await ref.read(apiClientProvider).askAssistant(history, text);
      if (!mounted) return;
      setState(() {
        _messages.add((role: 'assistant', content: reply));
        _capMessages();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'The assistant is unavailable right now.');
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  /// Keep memory bounded: drop the oldest pair once we exceed 40 entries.
  void _capMessages() {
    while (_messages.length > 40) {
      _messages.removeRange(0, 2);
    }
  }

  /// Reset the conversation. Clearing _messages makes the empty-state
  /// suggestion chips reappear (they render only when _messages is empty).
  void _clear() {
    setState(() {
      _messages.clear();
      _error = null;
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        // animateTo (not jumpTo): if the list is still laying out this frame,
        // the short animation re-reads maxScrollExtent as it settles, so the
        // newest bubble reliably ends up in view.
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final panelW = size.width - 40 < 380.0 ? size.width - 40 : 380.0;
    final panelH = size.height - 160 < 520.0 ? size.height - 160 : 520.0;

    // bottom offset: provider value (screens with a NavigationBar raise it)
    // plus system safe-area inset so we never clip under home indicator / nav bar.
    final providerBottom = ref.watch(chatbotBottomOffsetProvider);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final bottom = providerBottom + safeBottom;
    return Stack(
      children: [
        if (_open)
          Positioned(
            right: 16,
            bottom: bottom + 64,
            child: _panel(panelW, panelH),
          ),
        Positioned(
          right: 16,
          bottom: bottom,
          child: FloatingActionButton(
            heroTag: 'help_assistant_fab',
            backgroundColor: VColors.brand500,
            foregroundColor: VColors.contentOnAccent,
            onPressed: () => setState(() => _open = !_open),
            child: Icon(_open ? Icons.close_rounded : Icons.chat_bubble_outline_rounded),
          ),
        ),
      ],
    );
  }

  Widget _panel(double w, double h) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: VColors.surface800,
          borderRadius: BorderRadius.circular(VRadius.xl),
          border: Border.all(color: VColors.surface700, width: 1),
          boxShadow: const [
            BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(VSpace.x4),
              decoration: BoxDecoration(
                color: VColors.surface700.withValues(alpha: 0.6),
                border: Border(bottom: BorderSide(color: VColors.surface700)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: VColors.brand500.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(VRadius.full),
                    ),
                    child: Icon(Icons.auto_awesome_rounded,
                        size: 16, color: VColors.brand400),
                  ),
                  const SizedBox(width: VSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LogBook360 Assistant',
                            style: VType.label.copyWith(color: VColors.contentStrong)),
                        Text('Ask anything about using the app',
                            style: VType.caption.copyWith(fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Clear conversation',
                    onPressed: _messages.isEmpty ? null : _clear,
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 18, color: VColors.contentMuted),
                  ),
                ],
              ),
            ),
            // Messages
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(VSpace.x4),
                children: [
                  if (_messages.isEmpty) ...[
                    Text('Hi! I can help you use LogBook360. Try:',
                        style: VType.body),
                    const SizedBox(height: VSpace.x3),
                    for (final s in _suggestions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: VSpace.x2),
                        child: InkWell(
                          onTap: () => _send(s),
                          borderRadius: BorderRadius.circular(VRadius.md),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: VSpace.x3, vertical: VSpace.x3),
                            decoration: BoxDecoration(
                              color: VColors.surface700.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(VRadius.md),
                              border: Border.all(color: VColors.surface600),
                            ),
                            child: Text(s,
                                style: VType.caption
                                    .copyWith(color: VColors.contentDefault)),
                          ),
                        ),
                      ),
                  ],
                  for (final m in _messages) _bubble(m.role, m.content),
                  if (_busy)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(top: VSpace.x2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: VSpace.x3, vertical: VSpace.x3),
                        decoration: BoxDecoration(
                          color: VColors.surface700,
                          borderRadius: BorderRadius.circular(VRadius.lg),
                        ),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: VColors.contentMuted),
                        ),
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: VSpace.x2),
                      child: Text(_error!,
                          style: VType.caption.copyWith(color: VColors.alertDanger)),
                    ),
                ],
              ),
            ),
            // Composer
            Container(
              padding: const EdgeInsets.all(VSpace.x3),
              decoration: BoxDecoration(
                color: VColors.surface700.withValues(alpha: 0.4),
                border: Border(top: BorderSide(color: VColors.surface700)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      style: VType.body.copyWith(color: VColors.contentStrong),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(hintText: 'Ask a question…'),
                    ),
                  ),
                  const SizedBox(width: VSpace.x2),
                  IconButton.filled(
                    onPressed: _busy ? null : () => _send(),
                    style: IconButton.styleFrom(
                      backgroundColor: VColors.brand500,
                      foregroundColor: VColors.contentOnAccent,
                    ),
                    icon: const Icon(Icons.send_rounded, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(String role, String content) {
    final isUser = role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: VSpace.x2),
        padding: const EdgeInsets.symmetric(
            horizontal: VSpace.x3, vertical: VSpace.x3),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.6),
        decoration: BoxDecoration(
          color: isUser ? VColors.brand500 : VColors.surface700,
          borderRadius: BorderRadius.circular(VRadius.lg),
        ),
        child: Text(
          content,
          style: VType.body.copyWith(
            color: isUser ? VColors.contentOnAccent : VColors.contentDefault,
          ),
        ),
      ),
    );
  }
}
