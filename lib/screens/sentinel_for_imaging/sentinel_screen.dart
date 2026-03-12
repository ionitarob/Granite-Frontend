import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sentinel_provider.dart';

import 'sentinel_dashboard.dart';
import '../../services/api_service.dart';
import 'active_imaging_panel.dart';
import 'sentinel_theme.dart';
import 'dart:ui'; // For BackdropFilter

class SentinelScreen extends StatelessWidget {
  const SentinelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) {
        final provider = SentinelProvider();
        final user = Provider.of<ApiService>(
          context,
          listen: false,
        ).currentUser;
        if (user != null) {
          provider.setUserName(user.displayName());
        }
        return provider;
      },
      child: Theme(
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
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Active Imaging Interface (Left Side - 30%)
                    Expanded(
                      flex: 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            decoration: SentinelTheme.glassDecoration(
                              opacity: 0.05,
                              borderRadius: 16,
                            ),
                            child: const ActiveImagingPanel(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12), // Spacing instead of divider
                    // Dashboard (Right Side - 70%)
                    Expanded(
                      flex: 7,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            decoration: SentinelTheme.glassDecoration(
                              opacity: 0.05,
                              borderRadius: 16,
                            ),
                            child: const SentinelDashboard(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
