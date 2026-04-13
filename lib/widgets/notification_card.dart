import 'package:flutter/material.dart';
import '../services/notification_provider.dart';
import 'liquid_glass_card.dart';
import 'package:intl/intl.dart';

class NotificationCard extends StatelessWidget {
  final GraniteNotification notification;
  final VoidCallback? onTap;

  const NotificationCard({
    super.key,
    required this.notification,
    this.onTap,
  });

  IconData _getIcon() {
    switch (notification.tipo) {
      case 'contract_expiring':
        return Icons.assignment_late_rounded;
      case 'system_alert':
        return Icons.info_outline_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  Color _getColor() {
    switch (notification.tipo) {
      case 'contract_expiring':
        return Colors.orangeAccent;
      case 'system_alert':
        return Colors.blueAccent;
      default:
        return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return LiquidGlassCard(
      onTap: onTap,
      radius: 16,
      blur: 14,
      padding: const EdgeInsets.all(12),
      borderColor: notification.leido ? null : Colors.red.withValues(alpha: 0.3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _getColor().withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(_getIcon(), color: _getColor(), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        notification.titulo,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!notification.leido)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  notification.mensaje,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 12,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  _formatDate(notification.fechaCreacion),
                  style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    return DateFormat('dd/MM HH:mm').format(dt);
  }
}
