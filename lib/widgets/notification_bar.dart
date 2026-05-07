import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/notification_provider.dart';
import '../config.dart';
import '../services/api_service.dart';
import 'liquid_glass_card.dart';
import 'notification_card.dart';

class NotificationBar extends StatefulWidget {
  const NotificationBar({super.key});

  @override
  State<NotificationBar> createState() => _NotificationBarState();
}

class _NotificationBarState extends State<NotificationBar> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late final AnimationController _expandCtrl;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _expandAnim = CurvedAnimation(
      parent: _expandCtrl,
      curve: Curves.easeOutBack,
    );
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandCtrl.forward();
      } else {
        _expandCtrl.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Deactivated atm
    return const SizedBox.shrink();

    final provider = Provider.of<NotificationProvider>(context);

    // Skip showing the bar on Login and Splash screens (when no user is authenticated)
    if (provider.apiService.currentUser == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= 900;

    // Unread indicators
    final unread = provider.unreadCount;
    
    return Stack(
      children: [
        // Full screen hit-test layer for dismissal when expanded
        if (_isExpanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggle,
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),
          ),

        // The Bar Trigger
        Positioned(
          top: isDesktop ? null : 0,
          bottom: isDesktop ? 16 : null,
          right: isDesktop ? 16 : 0,
          left: isDesktop ? null : 0,
          child: SafeArea(
            bottom: isDesktop,
            top: !isDesktop,
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
              onVerticalDragUpdate: !isDesktop ? (details) {
                // Mobile: Swipe down to expand, swipe up to collapse
                if (details.primaryDelta! > 10 && !_isExpanded) {
                  _toggle();
                } else if (details.primaryDelta! < -10 && _isExpanded) {
                  _toggle();
                }
              } : (details) {
                // Desktop: Swipe up to expand, swipe down to collapse
                if (details.primaryDelta! < -10 && !_isExpanded) {
                  _toggle();
                } else if (details.primaryDelta! > 10 && _isExpanded) {
                  _toggle();
                }
              },
              onTap: _toggle,
              behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: (!isDesktop && !_isExpanded) ? 0.0 : 1.0,
                    child: LiquidGlassCard(
                      radius: isDesktop ? 12 : 20,
                      blur: _isExpanded ? 20 : 8,
                      elevated: _isExpanded,
                      padding: EdgeInsets.symmetric(
                        horizontal: 10, 
                        vertical: isDesktop ? 6 : 4,
                      ),
                      tint: isDark ? Colors.black.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isDesktop) ...[
                            // Mobile drag handle
                            Container(
                              width: 36,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 6, top: 2),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white12 : Colors.black12,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                children: [
                                  Icon(
                                    Icons.notifications_rounded,
                                    size: isDesktop ? 20 : 22,
                                    color: isDark ? Colors.white70 : Colors.black54,
                                  ),
                                  if (unread > 0)
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 10,
                                          minHeight: 10,
                                        ),
                                        child: Text(
                                          unread > 9 ? '9+' : '$unread',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 7,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              // Only show text and spacing on mobile or if expanded on desktop
                              if (!isDesktop || _isExpanded) ...[
                                const SizedBox(width: 8),
                                Text(
                                  'Notificaciones',
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black87,
                                    fontWeight: FontWeight.w700,
                                    fontSize: isDesktop ? 13 : 14,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  _isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                                  size: 18,
                                  color: isDark ? Colors.white38 : Colors.black26,
                                ),
                              ],
                            ],
                          ),
                          if (!isDesktop && _isExpanded) const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
                ),
            ),
          ),
        ),
      ),

        // Expanded Panel
        if (_isExpanded || _expandCtrl.isAnimating)
          Positioned(
            top: isDesktop ? null : 60,
            bottom: isDesktop ? 70 : null,
            right: 16,
            left: isDesktop ? null : 16,
            child: FadeTransition(
              opacity: _expandAnim,
              child: SizeTransition(
                sizeFactor: _expandAnim,
                axisAlignment: isDesktop ? 1 : -1, // Desktop: Expand upwards / Mobile: Downwards
                child: Material(
                  color: Colors.transparent,
                  child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isDesktop ? 340 : double.infinity,
                    maxHeight: size.height * 0.6,
                  ),
                  child: LiquidGlassCard(
                    padding: EdgeInsets.zero,
                    radius: 20,
                    blur: 25,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Centro de Notificaciones',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              if (unread > 0)
                                TextButton(
                                  onPressed: provider.markAllAsRead,
                                  child: const Text('Limpiar todo', style: TextStyle(fontSize: 12)),
                                ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, thickness: 0.5),
                        Flexible(
                          child: provider.isLoading && provider.notifications.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: CircularProgressIndicator(),
                                )
                              : provider.notifications.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.all(30),
                                      child: Column(
                                        children: [
                                          Icon(Icons.notifications_none_rounded, size: 40, color: isDark ? Colors.white24 : Colors.black12),
                                          const SizedBox(height: 10),
                                          Text('No tienes notificaciones', style: TextStyle(color: isDark ? Colors.white38 : Colors.black26)),
                                        ],
                                      ),
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.all(12),
                                      itemCount: provider.notifications.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                                      itemBuilder: (ctx, i) {
                                        final n = provider.notifications[i];
                                        return NotificationCard(
                                          notification: n,
                                          onTap: () {
                                            provider.markAsRead(n.id);
                                            // Handle deep link if present
                                            if (n.tipo == 'contract_expiring') {
                                              // Optional: Navigate to user management
                                              Navigator.of(context).pushNamed('/hr/gestion_empleado');
                                            }
                                          },
                                        );
                                      },
                                     ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
