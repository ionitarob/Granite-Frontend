import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'sentinel_provider.dart';
import 'sentinel_stats_dashboard.dart';
import 'sentinel_theme.dart';

class SentinelStatsScreen extends StatelessWidget {
  const SentinelStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SentinelProvider>(
      builder: (context, provider, _) {
        return Theme(
          data: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xFF121212),
            colorScheme: const ColorScheme.dark(
              primary: Colors.cyanAccent,
              secondary: Colors.blueAccent,
            ),
          ),
          child: Scaffold(
            extendBodyBehindAppBar: true,
            body: Container(
              decoration: const BoxDecoration(
                gradient: SentinelTheme.backgroundGradient,
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Row(
                        children: [
                          const Icon(Icons.bar_chart_rounded, color: Colors.cyanAccent, size: 24),
                          const SizedBox(width: 12),
                          const Text(
                            'SENTINEL · ESTADÍSTICAS',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white54),
                            tooltip: 'Volver',
                          ),
                        ],
                      ),
                    ),
                    // Stats Dashboard
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              decoration: SentinelTheme.glassDecoration(opacity: 0.05, borderRadius: 16),
                              padding: const EdgeInsets.all(24),
                              child: SentinelStatsDashboard(service: provider.service),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
