import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sentinel_provider.dart';
import 'sentinel_chat.dart';
import 'sentinel_dashboard.dart';
import '../../services/api_service.dart';

class SentinelScreen extends StatelessWidget {
  const SentinelScreen({Key? key}) : super(key: key);

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
          body: Row(
            children: [
              // Chat Interface (Left Side - 30%)
              const Expanded(flex: 3, child: SentinelChat()),
              Container(width: 1, color: Colors.white10),
              // Dashboard (Right Side - 70%)
              const Expanded(flex: 7, child: SentinelDashboard()),
            ],
          ),
        ),
      ),
    );
  }
}
