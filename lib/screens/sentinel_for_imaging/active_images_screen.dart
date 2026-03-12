import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import 'sentinel_provider.dart';
import 'active_imaging_panel.dart';
import 'sentinel_theme.dart';
import '../../widgets/main_sidebar.dart';

class ActiveImagesScreen extends StatefulWidget {
  const ActiveImagesScreen({super.key});

  @override
  State<ActiveImagesScreen> createState() => _ActiveImagesScreenState();
}

class _ActiveImagesScreenState extends State<ActiveImagesScreen> {
  OverlayEntry? _edgeOverlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final routeName = ModalRoute.of(context)?.settings.name;
        final overlay = Overlay.of(context, rootOverlay: true);
        _edgeOverlay = OverlayEntry(
          builder: (ctx) {
            return Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: SafeArea(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: EdgeNavHandle(
                    user: Provider.of<ApiService>(
                      ctx,
                      listen: false,
                    ).currentUser,
                    width: 32,
                    currentRoute: routeName,
                    showIndicator: true,
                  ),
                ),
              ),
            );
          },
        );
        overlay.insert(_edgeOverlay!);
      }
    });
  }

  @override
  void dispose() {
    _edgeOverlay?.remove();
    _edgeOverlay = null;
    super.dispose();
  }

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
            surface: Color(0xFF2C2C2C),
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
                padding: const EdgeInsets.all(24),
                child: Container(
                  decoration: SentinelTheme.glassDecoration(
                    opacity: 0.05,
                    borderRadius: 16,
                    border: true,
                  ),
                  child: const ActiveImagingPanel(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
