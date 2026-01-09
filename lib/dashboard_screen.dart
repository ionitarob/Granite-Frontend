import 'dart:ui';
import 'package:flutter/material.dart';

import 'widgets/main_sidebar.dart';
import 'widgets/animated_background.dart';
import 'widgets/total_grading_widget.dart';
import 'widgets/grading_hoy_widget.dart';
import 'widgets/widget_grid.dart';
import 'widgets/grading_series_widget.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'models/user_model.dart';
import 'config.dart';

class DashboardScreen extends StatefulWidget {
  final User? user;

  const DashboardScreen({Key? key, this.user}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Color?> _graniteColor;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _graniteColor = ColorTween(
      begin: Colors.red,
      end: Colors.white,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _ctrl.repeat(reverse: true);
  }

  // Bump this to force WidgetGrid to reinitialize when layout changes.
  int _widgetGridRevision = 0;

  Future<void> _addWidgetToLayout(String storageKey, String widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final raw = prefs.getString(storageKey);
    List layout;
    if (raw != null) {
      try {
        layout = json.decode(raw) as List;
      } catch (_) {
        layout = [];
      }
    } else {
      layout = [];
    }

    // Place into first null slot if present, otherwise append
    final nullIndex = layout.indexWhere((e) => e == null);
    if (nullIndex >= 0) {
      layout[nullIndex] = widgetId;
    } else {
      layout.add(widgetId);
    }

    await prefs.setString(storageKey, json.encode(layout));
    setState(() => _widgetGridRevision++);
  }

  Future<void> _onAddWidgetPressed(BuildContext ctx) async {
    // Use this state's context for synchronous lookups to avoid holding on to
    // the caller's BuildContext across async gaps.
    final api = Provider.of<ApiService>(context, listen: false);
    final u =
        widget.user ?? api.currentUser ?? User(username: 'demo', role: 'admin');
    final storageKey = 'widget_layout_${u.username}';

    // Available widgets (same keys used by WidgetGrid)
    final available = <String, String>{
      'total_grading': 'Total grading',
      'grading_hoy': 'Grading Hoy',
      'grading_series': 'Grading Series',
    };

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    List existing = [];
    if (raw != null) {
      try {
        existing = json.decode(raw) as List;
      } catch (_) {
        existing = [];
      }
    } else {
      // default: assume nothing persisted yet
      existing = [];
    }

    final present = <String>{};
    for (final e in existing) {
      if (e is String) present.add(e);
    }

    final remaining = available.keys
        .where((k) => !present.contains(k))
        .toList();
    if (remaining.isEmpty) {
      // Use the State's context after async gaps to avoid build-context warnings
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more widgets available to add')),
      );
      return;
    }

    final selected = await showDialog<String?>(
      context: context,
      builder: (dctx) => SimpleDialog(
        title: const Text('Add widget'),
        children: remaining
            .map(
              (id) => SimpleDialogOption(
                onPressed: () => Navigator.of(dctx).pop(id),
                child: Text(available[id] ?? id),
              ),
            )
            .toList(),
      ),
    );

    if (!mounted) return;
    if (selected != null) {
      await _addWidgetToLayout(storageKey, selected);
    }
  }

  // Central content area shared by desktop and mobile layouts.
  Widget _buildMainContent(ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          const SizedBox(height: 8),
          // Prominent "Dashboard" Title (macOS style header)
          Text(
            'Dashboard',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: theme.textTheme.headlineLarge?.color,
            ),
          ),
          const SizedBox(height: 20),

          // Widgets area (replaces quick tiles) — build as a separate body so
          // mobile can include it inside the page-level scroll.
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: _buildMainContentBody(theme, colorScheme),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // The inner content block that holds widgets; reused by desktop and mobile
  Widget _buildMainContentBody(ThemeData theme, ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? Colors.black.withOpacity(0.2)
                : Colors.white.withOpacity(
                    0.15,
                  ), // Reduced from 0.3 for better visibility
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Widgets Bar',
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color?.withOpacity(0.8),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // + button for adding widgets
                  Container(
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: () => _onAddWidgetPressed(context),
                      icon: const Icon(Icons.add_rounded),
                      color: theme.textTheme.bodyLarge?.color,
                      tooltip: 'Add widget',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // WidgetGrid: provides responsive slots, drag/drop and persistence per-user
              Builder(
                builder: (ctx) {
                  final u =
                      widget.user ??
                      Provider.of<ApiService>(ctx, listen: false).currentUser ??
                      User(username: 'demo', role: 'admin');
                  final available = <String, Widget>{
                    'total_grading': TotalGradingWidget(),
                    'grading_hoy': GradingHoyWidget(),
                    'grading_series': GradingSeriesWidget(),
                  };
                  final spans = <String, int>{'grading_series': 2};
                  return WidgetGrid(
                    key: ValueKey(_widgetGridRevision),
                    availableWidgets: available,
                    storageKey: 'widget_layout_${u.username}',
                    spanColumns: spans,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,

      // Removed AppBar for full-height sidebar and macOS aesthetic
      body: Stack(
        children: [
          // Animated background that adapts to Bright/Dark theme
          const AnimatedBackgroundWidget(intensity: 1.0),

          // Content: show permanent sidebar on wide screens; on mobile show
          // a compact header with an EdgeNavHandle and the main content full-width.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Builder(
                builder: (ctx) {
                  final isMobileInner = MediaQuery.of(ctx).size.width < 900;
                  final u =
                      widget.user ??
                      Provider.of<ApiService>(ctx, listen: false).currentUser ??
                      User(username: 'demo', role: 'admin');
                  if (!isMobileInner) {
                    // Desktop: permanent sidebar + content
                    final routeName = ModalRoute.of(context)?.settings.name;
                    return Row(
                      children: [
                        MainSidebar(
                          user: u,
                          permanent: true,
                          currentRoute: routeName,
                        ),
                        Expanded(child: _buildMainContent(theme, colorScheme)),
                      ],
                    );
                  }

                  // Mobile: header with edge handle + full-width content
                  return Column(
                    children: [
                      Container(
                        height: 72,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: theme.cardColor.withAlpha(6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SafeArea(
                          child: Stack(
                            children: [
                              Positioned(
                                left: 0,
                                top: 0,
                                bottom: 0,
                                child: EdgeNavHandle(user: u),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Allow the whole page to scroll on mobile so users can scroll
                      // down to see more widgets. We reuse the inner body to avoid
                      // duplicating widget layout.
                      Expanded(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20.0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 6),
                                Text(
                                  'Dashboard',
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildMainContentBody(theme, colorScheme),
                                const SizedBox(height: 40),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          // Animated, interactive AI Sphere in bottom-right
          const _AispherePosition(),
        ],
      ),
    );
  }
}

// Small widget that shows the animated AI sphere in the bottom-right.
// It plays the provided Lottie animation and reacts to mouse hover by growing
// slightly and adding a glow.
class _AispherePosition extends StatelessWidget {
  const _AispherePosition({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Provide a finite sized container so the inner Stack in _Aisphere has
    // bounded constraints (it needs finite width/height to layout the chat
    // panel above the sphere). The size covers the chat panel + sphere.
    return Positioned(
      right: 20,
      bottom: 20,
      // make the wrapper compact so the sphere is clearly visible at
      // bottom-right; the ChatPanel will still position itself above the
      // sphere using the internal Stack.
      child: SizedBox(width: 120, height: 120, child: _Aisphere()),
    );
  }
}

class _Aisphere extends StatefulWidget {
  const _Aisphere({Key? key}) : super(key: key);

  @override
  State<_Aisphere> createState() => _AisphereState();
}

class _AisphereState extends State<_Aisphere> {
  bool _hover = false;
  bool _chatOpen = false;
  final GlobalKey<_ChatPanelState> _panelKey = GlobalKey<_ChatPanelState>();

  void _setHover(bool v) {
    // Schedule hover state changes after the current frame to avoid
    // mutating widget tree during layout/device updates which can cause
    // assertions like '!_debugDoingThisLayout' or mouse tracker errors.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _hover = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    // size adjusts with hover (kept intentionally small)
    final size = _hover ? 72.0 : 56.0;

    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      cursor: SystemMouseCursors.click,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_chatOpen)
            Positioned(
              right: 0,
              bottom: 72.0,
              child: ChatPanel(
                key: _panelKey,
                onClose: () => setState(() => _chatOpen = false),
              ),
            ),

          // Only the sphere itself is gesture-aware now. The ChatPanel is a
          // sibling so clicks inside it won't toggle the sphere or steal focus.
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTapDown: (_) => _setHover(true),
              onTapUp: (_) => _setHover(false),
              onTapCancel: () => _setHover(false),
              onTap: () => WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final newOpen = !_chatOpen;
                setState(() => _chatOpen = newOpen);
                if (newOpen) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _panelKey.currentState?.requestFocus();
                  });
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.blue.shade700.withAlpha(220),
                      Colors.black.withAlpha(10),
                    ],
                    center: const Alignment(-0.4, -0.6),
                    radius: 0.9,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blueAccent.withAlpha(_hover ? 80 : 40),
                      blurRadius: _hover ? 10 : 4,
                      spreadRadius: _hover ? 1 : 0,
                    ),
                  ],
                ),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  scale: _hover ? 1.06 : 1.0,
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: ClipOval(
                      child: Material(
                        color: Colors.transparent,
                        child: SizedBox.expand(
                          child: Center(
                            child: LottieBuilder.asset(
                              'lib/assets/AI Sphere.json',
                              fit: BoxFit.contain,
                              repeat: true,
                              animate: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatPanel extends StatefulWidget {
  final VoidCallback? onClose;
  const ChatPanel({Key? key, this.onClose}) : super(key: key);

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final List<Map<String, String>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;
  http.Client? _httpClient;
  StreamSubscription<String>? _streamSub;
  bool _aborted = false;

  // Called by parent to move keyboard focus into the input field.
  void requestFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _sending = true;
      _controller.clear();
    });
    // schedule scrolling after this frame to avoid changing layout during
    // the current frame which can trigger rendering assertions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        try {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent + 120,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        } catch (_) {}
      }
    });

    try {
      // Use centralized backend base URL so the app respects `kBackendBaseUrl`.
      final uri = Uri.parse('$kBackendBaseUrl/ask');
      // Prepare client/request to read streamed SSE (server-sent events)
      _httpClient = http.Client();
      final req = http.Request('POST', uri)
        ..headers['Content-Type'] = 'application/json'
        ..body = json.encode({'prompt': text});

      // Add an empty assistant entry that we'll fill progressively
      int assistantIndex = -1;
      setState(() {
        _messages.add({'role': 'assistant', 'text': ''});
        assistantIndex = _messages.length - 1;
      });

      final streamed = await _httpClient!
          .send(req)
          .timeout(const Duration(seconds: 20));
      if (streamed.statusCode != 200) {
        final body = await streamed.stream.bytesToString();
        setState(() {
          _messages[assistantIndex]['text'] =
              'Error ${streamed.statusCode}: $body';
          _sending = false;
        });
        return;
      }

      // Listen to the byte stream, decode UTF8 and parse SSE events separated by "\n\n"
      final decoder = streamed.stream.transform(utf8.decoder);
      String buffer = '';
      _aborted = false;
      _streamSub = decoder.listen(
        (chunk) {
          if (_aborted) return;
          buffer += chunk;
          // Extract complete events separated by double-newline
          while (true) {
            final idx = buffer.indexOf('\n\n');
            if (idx < 0) break;
            final event = buffer.substring(0, idx);
            buffer = buffer.substring(idx + 2);
            // Each event may have multiple lines. We only process lines that start with 'data:'
            for (final line in event.split('\n')) {
              if (line.trim().isEmpty) continue;
              if (line.startsWith('data:')) {
                var chunkText = line.substring(5).trim();
                // Server may escape newlines as literal '\\n' — unescape those
                chunkText = chunkText.replaceAll('\\n', '\n');
                // Handle [DONE] sentinel
                if (chunkText.trim() == '[DONE]') {
                  continue;
                }
                // Append chunk to assistant message
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final prev = _messages[assistantIndex]['text'] ?? '';
                  _messages[assistantIndex]['text'] = prev + chunkText;
                  // keep UI responsive by updating state
                  setState(() {});
                  // auto-scroll
                  if (_scroll.hasClients) {
                    try {
                      _scroll.animateTo(
                        _scroll.position.maxScrollExtent + 120,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                      );
                    } catch (_) {}
                  }
                });
              }
            }
          }
        },
        onDone: () async {
          // If there's leftover buffer with a final event, process it quickly
          if (buffer.isNotEmpty && !_aborted) {
            for (final line in buffer.split('\n')) {
              if (line.startsWith('data:')) {
                var chunkText = line.substring(5).trim();
                chunkText = chunkText.replaceAll('\\n', '\n');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final prev = _messages[assistantIndex]['text'] ?? '';
                  _messages[assistantIndex]['text'] = prev + chunkText;
                  setState(() {});
                });
              }
            }
          }
          _httpClient?.close();
          _httpClient = null;
          _streamSub = null;
          if (!mounted) return;
          setState(() {
            _sending = false;
          });
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _messages.add({'role': 'assistant', 'text': 'Stream error: $e'});
            _sending = false;
          });
        },
        cancelOnError: true,
      );
    } catch (e) {
      setState(() {
        _messages.add({'role': 'assistant', 'text': 'Network error: $e'});
        _sending = false;
      });
    } finally {
      // final state is set in onDone/onError of the stream; but ensure flag is clear if something left it on
      if (mounted) setState(() => _sending = false);
    }
    // after assistant reply, schedule scroll-to-bottom after the frame completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        try {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent + 120,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    _streamSub?.cancel();
    _httpClient?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 360,
        height: 480,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Header with Sentinel name and close
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 10.0,
              ),
              child: Row(
                children: [
                  const CircleAvatar(child: Text('S')),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Sentinel',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Messages list
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: _messages.length,
                  itemBuilder: (ctx, i) {
                    final m = _messages[i];
                    final isUser = m['role'] == 'user';
                    final bubbleColor = isUser
                        ? theme.colorScheme.primary
                        : theme.dividerColor.withAlpha(30);
                    final textColor = isUser
                        ? Colors.white
                        : theme.textTheme.bodyMedium?.color ?? Colors.black87;
                    return Align(
                      alignment: isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 240),
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 4,
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 14,
                          ),
                          decoration: BoxDecoration(
                            color: bubbleColor,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isUser ? 16 : 4),
                              bottomRight: Radius.circular(isUser ? 4 : 16),
                            ),
                          ),
                          child: Text(
                            m['text'] ?? '',
                            style: TextStyle(color: textColor),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const Divider(height: 1),

            // Input row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            theme.inputDecorationTheme.fillColor ??
                            theme.cardColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Focus(
                              onKey: (node, event) {
                                // Send on Enter, allow Shift+Enter to insert newline
                                if (event is RawKeyDownEvent &&
                                    event.logicalKey ==
                                        LogicalKeyboardKey.enter) {
                                  final isShift = event.isShiftPressed;
                                  if (!isShift) {
                                    _send();
                                    return KeyEventResult.handled;
                                  } else {
                                    // Insert newline at cursor
                                    final sel = _controller.selection;
                                    final textBefore = _controller.text
                                        .substring(0, sel.start);
                                    final textAfter = _controller.text
                                        .substring(sel.end);
                                    final newText = '$textBefore\n$textAfter';
                                    final newPos = (textBefore + '\n').length;
                                    _controller.text = newText;
                                    _controller.selection =
                                        TextSelection.collapsed(offset: newPos);
                                    return KeyEventResult.handled;
                                  }
                                }
                                return KeyEventResult.ignored;
                              },
                              child: TextField(
                                focusNode: _focus,
                                controller: _controller,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  hintText: 'Message',
                                ),
                                minLines: 1,
                                maxLines: 4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _sending
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : GestureDetector(
                          onTap: _send,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 20,
                            ),
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

// _DashboardTile removed — widgets area now uses a draggable, persistent WidgetGrid.
