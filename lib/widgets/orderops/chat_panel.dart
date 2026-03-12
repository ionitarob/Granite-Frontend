import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/agent_models.dart';
import '../../services/orderops_service.dart';
import '../../services/api_service.dart';

class ChatPanel extends StatefulWidget {
  final int orderId;

  const ChatPanel({super.key, required this.orderId});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _isStreaming = false;
  String? _error;

  OrderOpsService? _service;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_service == null) {
      final apiService = Provider.of<ApiService>(context);
      _service = OrderOpsService(apiService.client);
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final msgs = await _service!.getChatHistory(widget.orderId);
      if (mounted) {
        setState(() {
          _messages = msgs;
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isStreaming) return;

    _controller.clear();
    setState(() {
      _isStreaming = true;
      // Optimistic user message
      _messages.add(
        ChatMessage(role: 'human', content: text, createdAt: DateTime.now()),
      );
      // Placeholder for assistant
      _messages.add(
        ChatMessage(role: 'assistant', content: '', isStreaming: true),
      );
    });
    _scrollToBottom();

    try {
      final stream = _service!.streamChat(widget.orderId, text);

      String accumulatedText = '';

      await for (final event in stream) {
        final type = event['event'];
        final data = event['data']; // likely Map

        if (type == 'delta') {
          // Check 'delta' first as per user spec, fallback to 'content'
          final content =
              data['delta'] as String? ?? data['content'] as String? ?? '';
          accumulatedText += content;

          if (mounted) {
            setState(() {
              // Update last message
              final last = _messages.last;
              if (last.isStreaming && last.role == 'assistant') {
                _messages[_messages.length - 1] = ChatMessage(
                  role: 'assistant',
                  content: accumulatedText,
                  isStreaming: true,
                );
              }
            });
            // Auto scroll near bottom?
            // _scrollToBottom(); // Can be annoying if reading back
          }
        } else if (type == 'done') {
          final finalId = data['assistant_message_id'] as int?;
          // final fullText = data['text'] as String?; // Optional check

          if (mounted) {
            setState(() {
              _messages[_messages.length - 1] = ChatMessage(
                id: finalId,
                role: 'assistant',
                content: accumulatedText, // or fullText ?? accumulatedText
                isStreaming: false,
                createdAt: DateTime.now(),
              );
            });
          }
        } else if (type == 'error') {
          // Handle stream error from backend
          throw Exception(data['message'] ?? 'Stream error');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // Mark streaming as failed or add error message
          _messages[_messages.length - 1] = ChatMessage(
            role: 'assistant',
            content: '${_messages.last.content}\n[Error: $e]',
            isStreaming: false,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStreaming = false;
        });
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Theme override for dark chat UI? Or use global theme.
    final theme = Theme.of(context);

    return Column(
      children: [
        if (_error != null)
          Container(
            color: Colors.red.withOpacity(0.1),
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                const Icon(Icons.error, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!)),
                IconButton(
                  onPressed: _loadHistory,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, index) {
              final msg = _messages[index];
              return _buildMessage(theme, msg);
            },
          ),
        ),
        _buildInput(theme),
      ],
    );
  }

  Widget _buildMessage(ThemeData theme, ChatMessage msg) {
    final isHuman = msg.role == 'human';
    final align = isHuman ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    // Ensure high contrast for the dark overlay
    final color = isHuman ? theme.colorScheme.primary : Colors.grey[800];
    // Force specific text color if theme contrast is failing
    final textColor = isHuman ? Colors.white : Colors.white;

    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16).copyWith(
              bottomRight: isHuman ? Radius.zero : null,
              bottomLeft: isHuman ? null : Radius.zero,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                msg.content,
                style: theme.textTheme.bodyLarge?.copyWith(color: textColor),
              ),
              if (msg.isStreaming)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: SizedBox(
                    height: 10,
                    width: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: textColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isHuman ? 'Tú' : 'Agente (C.O.P)',
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildInput(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_isStreaming,
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje al agente...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            mini: true,
            onPressed: _isStreaming ? null : _sendMessage,
            child: _isStreaming
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
