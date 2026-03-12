import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'sentinel_provider.dart';
import 'sentinel_theme.dart';

class SentinelChat extends StatefulWidget {
  const SentinelChat({super.key});

  @override
  State<SentinelChat> createState() => _SentinelChatState();
}

class _SentinelChatState extends State<SentinelChat> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SentinelProvider>(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Container(
      color: Colors.transparent, // Handled by parent glass container
      child: Column(
        children: [
          // Chat Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: SentinelTheme.primary.withOpacity(0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: SentinelTheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: SentinelTheme.primary.withOpacity(0.2),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.security,
                    color: SentinelTheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SENTINEL AI', style: SentinelTheme.header),
                    Text(
                      'Online',
                      style: SentinelTheme.label.copyWith(
                        color: SentinelTheme.success,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (provider.isListening)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: SentinelTheme.glowDecoration(
                      color: SentinelTheme.error,
                      opacity: 0.1,
                      glowOpacity: 0.2,
                      borderRadius: 12,
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.mic, color: SentinelTheme.error, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'Listening...',
                          style: TextStyle(
                            color: SentinelTheme.error,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Messages Area
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              // Add 1 to execute thinking bubble logic if thinking
              itemCount:
                  provider.chatMessages.length + (provider.isThinking ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == provider.chatMessages.length) {
                  return const _ThinkingBubble();
                }

                final msg = provider.chatMessages[index];
                final isUser = msg['role'] == 'user';
                return _MessageBubble(
                  message: msg['message'] ?? '',
                  isUser: isUser,
                );
              },
            ),
          ),
          // Input Area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: SentinelTheme.primary.withOpacity(0.1)),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    provider.isListening ? Icons.mic : Icons.mic_none_rounded,
                    color: provider.isListening
                        ? SentinelTheme.error
                        : SentinelTheme.textSecondary,
                  ),
                  onPressed: () {
                    if (provider.isListening) {
                      provider.stopListening();
                    } else {
                      provider.startListening();
                    }
                  },
                  tooltip: 'Voice Input',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: TextField(
                      controller: _controller,
                      style: SentinelTheme.body.copyWith(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Type a command or query...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                      onSubmitted: (value) {
                        if (value.isNotEmpty) {
                          provider.sendMessage(value);
                          _controller.clear();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: SentinelTheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: SentinelTheme.primary.withOpacity(0.2),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded),
                    color: SentinelTheme.primary,
                    onPressed: () {
                      if (_controller.text.isNotEmpty) {
                        provider.sendMessage(_controller.text);
                        _controller.clear();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 4),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: SentinelTheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: SentinelTheme.primary.withOpacity(0.3),
                ),
              ),
              child: const Icon(
                Icons.security,
                color: SentinelTheme.primary,
                size: 14,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration:
                  SentinelTheme.glassDecoration(
                    borderRadius: 16,
                    opacity: 0.05,
                    border: true,
                  ).copyWith(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(4),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Thinking...',
                    style: SentinelTheme.body.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
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

class _MessageBubble extends StatelessWidget {
  final String message;
  final bool isUser;

  const _MessageBubble({required this.message, required this.isUser});

  String _parseMessage(String rawMessage) {
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is Map && decoded.containsKey('reply')) {
        return decoded['reply'].toString();
      }
    } catch (_) {
      // Not JSON or parse error, return original
    }
    return rawMessage;
  }

  @override
  Widget build(BuildContext context) {
    final displayMessage = isUser ? message : _parseMessage(message);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: SentinelTheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: SentinelTheme.primary.withOpacity(0.3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: SentinelTheme.primary.withOpacity(0.2),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.security,
                  color: SentinelTheme.primary,
                  size: 14,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isUser
                      ? SentinelTheme.secondary.withOpacity(0.15)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  border: Border.all(
                    color: isUser
                        ? SentinelTheme.secondary.withOpacity(0.3)
                        : Colors.white.withOpacity(0.1),
                  ),
                  boxShadow: [
                    if (isUser)
                      BoxShadow(
                        color: SentinelTheme.secondary.withOpacity(0.05),
                        blurRadius: 8,
                      ),
                  ],
                ),
                child: Text(
                  displayMessage,
                  style: SentinelTheme.body.copyWith(
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
            ),
            if (isUser) ...[
              const SizedBox(width: 12),
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: SentinelTheme.secondary.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: SentinelTheme.secondary.withOpacity(0.3),
                  ),
                ),
                child: const Icon(
                  Icons.person,
                  color: SentinelTheme.secondary,
                  size: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
