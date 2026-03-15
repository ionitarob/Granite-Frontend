import 'dart:math' as math;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'package:configtool_granite_frontend/services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';
// lottie was previously used for the header animation; replaced with a lightweight emoji animation.
import 'package:configtool_granite_frontend/dashboard_screen.dart';
import 'models/user_model.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// Simple animated background: radial gradients that slowly shift and subtle moving highlights.
class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({super.key});

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final List<_Blob> _blobs = [];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Initialize random blobs
    final rng = math.Random();
    for (int i = 0; i < 5; i++) {
      _blobs.add(
        _Blob(
          x: rng.nextDouble(),
          y: rng.nextDouble(),
          vx: (rng.nextDouble() - 0.5) * 0.002, // Slow movement
          vy: (rng.nextDouble() - 0.5) * 0.002,
          radius: 0.4 + rng.nextDouble() * 0.4, // Large creates blending
          phase: rng.nextDouble() * 2 * math.pi,
        ),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        final theme = Theme.of(context);
        final dark = theme.brightness == Brightness.dark;

        // Define palette based on theme
        final List<Color> palette = dark
            ? [
                const Color(0xFF0F0518), // Deep purple base
                const Color(0xFF4A1984), // Brighter purple
                const Color(0xFF2B0B55),
                const Color(0xFFD61C62).withOpacity(0.6), // Stronger Accent
                Theme.of(context).colorScheme.primary.withOpacity(0.4),
              ]
            : [
                const Color(0xFFE0E5EC), // Slightly darker grey-blue base
                const Color(0xFFB8C6DB), // Visible blue-grey
                const Color(0xFFF5D020).withOpacity(0.4), // Warm accent (Sun)
                const Color(0xFFA18CD1).withOpacity(0.4), // Purple accent
                Theme.of(context).colorScheme.primary.withOpacity(0.2),
              ];

        // Update blob positions slightly based on time
        for (var blob in _blobs) {
          blob.update();
        }

        return Container(
          color: palette.first, // Background base
          child: CustomPaint(
            painter: _AuroraPainter(
              blobs: _blobs,
              palette: palette,
              t: t,
              isDark: dark,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _Blob {
  double x;
  double y;
  double vx;
  double vy;
  double radius;
  double phase;

  _Blob({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.phase,
  });

  void update() {
    // Lissajous-like movement with boundary bounce
    x += vx;
    y += vy;
    // Soft bounce with some margin to keep blobs on screen
    if (x < -0.3 || x > 1.3) vx = -vx;
    if (y < -0.3 || y > 1.3) vy = -vy;
  }
}

class _AuroraPainter extends CustomPainter {
  final List<_Blob> blobs;
  final List<Color> palette;
  final double t;
  final bool isDark;

  _AuroraPainter({
    required this.blobs,
    required this.palette,
    required this.t,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // We paint multiple radial gradients for a "mesh" effect
    for (int i = 0; i < blobs.length; i++) {
      final blob = blobs[i];
      // color selection loops through palette, skipping index 0 (bg)
      final color = palette[(i % (palette.length - 1)) + 1];

      // Dynamic pulsing
      final pulse = math.sin(t * 2 * math.pi + blob.phase) * 0.1;

      final paint = Paint()
        ..shader =
            RadialGradient(
              colors: [
                color.withOpacity(isDark ? 0.6 : 0.4), // Higher opacity
                color.withOpacity(0.0),
              ],
              stops: const [0.0, 1.0],
            ).createShader(
              Rect.fromCircle(
                center: Offset(blob.x * size.width, blob.y * size.height),
                radius: size.shortestSide * (blob.radius + pulse),
              ),
            )
        // Use srcOver for light mode to ensure colors are visible against white
        // Use screen for dark mode for glowing effect
        ..blendMode = isDark ? BlendMode.screen : BlendMode.srcOver;

      canvas.drawRect(rect, paint);
    }

    // Optional: Subtle noise/dots on top for texture
    final noisePaint = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..strokeWidth = 1.0;

    final rng = math.Random(42); // Seeded for static noise pattern
    for (int i = 0; i < 100; i++) {
      double dx = rng.nextDouble() * size.width;
      double dy = rng.nextDouble() * size.height;
      canvas.drawPoints(PointMode.points, [Offset(dx, dy)], noisePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) => true;
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _remember = false;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _capsLock = false;
  String? _usernameError;
  String? _passwordError;
  final FocusNode _keyboardFocus = FocusNode();
  late final FocusNode _usernameFocus;
  late final FocusNode _passwordFocus;
  late final AnimationController _titleController;
  // Hover / interaction state
  // Keep only the fields currently used by the UI.

  final bool _updatesHover = false;

  // Update/info state
  bool _updatesLoading = true;
  bool _updateError = false;
  String? _serverVersion;
  String? _patchUrl;
  String? _descargaUrl;
  String? _cambiosText;
  String? _clientVersion;
  // Download state
  bool _downloading = false;
  // progress stored in notifier
  String? _downloadingName;
  http.Client? _activeDownloadClient;
  // Notifiers so dialogs can observe download progress
  final ValueNotifier<bool> _downloadingNotifier = ValueNotifier(false);
  final ValueNotifier<double> _downloadProgressNotifier = ValueNotifier(0.0);
  final ValueNotifier<String?> _downloadingNameNotifier = ValueNotifier(null);

  static const _savedUsernameKey = 'saved_username_v1';
  // Use the shared ApiService via Provider at call time so the app-wide
  // ApiClient receives tokens and cookie state.

  @override
  void initState() {
    super.initState();
    _loadSavedUsername();
    _usernameFocus = FocusNode()..addListener(() => setState(() {}));
    _passwordFocus = FocusNode()..addListener(() => setState(() {}));
    // Ensure RawKeyboardListener receives key events
    _keyboardFocus.requestFocus();

    // Fetch update information from backend
    _fetchUpdateInfo();

    _titleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  Future<void> _fetchUpdateInfo() async {
    setState(() {
      _updatesLoading = true;
      _updateError = false;
    });
    try {
      // Read local package version to report to the backend
      try {
        final pkg = await PackageInfo.fromPlatform();
        _clientVersion = pkg.version;
      } catch (_) {
        _clientVersion = null;
      }

      final apiService = Provider.of<ApiService>(context, listen: false);
      // Build path with optional version and platform query params.
      final platformStr = () {
        if (Platform.isAndroid) return 'android';
        if (Platform.isWindows) return 'windows';
        if (Platform.isLinux) return 'linux';
        if (Platform.isMacOS) return 'macos';
        return 'other';
      }();

      final verQuery = _clientVersion != null
          ? '?version=${Uri.encodeComponent(_clientVersion!)}&platform=$platformStr'
          : '?platform=$platformStr';
      final res = await apiService.client.get('/updates/version$verQuery');
      if (!mounted) return;
      if (res.ok && res.body != null && res.body is Map) {
        final mb = res.body as Map;
        final base = apiService.client.baseUrl;
        String? descarga = mb['descarga']?.toString();
        String? patch = mb['patch']?.toString();
        // Construct absolute URLs if server returned relative paths
        if (descarga != null &&
            descarga.isNotEmpty &&
            !descarga.startsWith('http')) {
          descarga = base + descarga;
        }
        if (patch != null && patch.isNotEmpty && !patch.startsWith('http')) {
          patch = base + patch;
        }

        setState(() {
          _serverVersion = mb['version']?.toString();
          _descargaUrl = descarga;
          _patchUrl = patch;
          _cambiosText = mb['cambios']?.toString() ?? mb['cambios']?.toString();
        });
      } else {
        setState(() => _updateError = true);
      }
    } catch (e) {
      setState(() => _updateError = true);
    } finally {
      if (mounted) setState(() => _updatesLoading = false);

      // Auto-trigger update if available
      if (_updateAvailable && mounted) {
        // Redirect iOS/macOS users immediately if update is required
        if (Platform.isIOS || Platform.isMacOS) {
          _showUpdatesDialog(context);
          return;
        }

        final url = _patchUrl ?? _descargaUrl;
        if (url != null) {
          _startDownload(url);
          _showUpdatesDialog(context);
        }
      }
    }
  }

  Future<void> _startDownload(String url) async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _downloadingName =
          Uri.tryParse(url)?.pathSegments.last ?? 'download.file';
    });
    _downloadingNotifier.value = true;
    _downloadProgressNotifier.value = 0.0;
    _downloadingNameNotifier.value = _downloadingName;

    final client = http.Client();
    _activeDownloadClient = client;
    try {
      final uri = Uri.parse(url);
      final req = http.Request('GET', uri);
      final streamed = await client.send(req);

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw Exception('HTTP ${streamed.statusCode}');
      }

      final total = streamed.contentLength ?? -1;
      // Prefer saving installers to a publicly-accessible downloads directory on Android
      // so the system package installer can access the APK. Fall back to temporary
      // directory if external storage isn't available.
      Directory chosenDir;
      try {
        if (Platform.isAndroid) {
          final exts = await getExternalStorageDirectories(
            type: StorageDirectory.downloads,
          );
          if (exts != null && exts.isNotEmpty) {
            chosenDir = exts.first;
          } else {
            chosenDir = await getTemporaryDirectory();
          }
        } else {
          chosenDir = await getTemporaryDirectory();
        }
      } catch (_) {
        chosenDir = await getTemporaryDirectory();
      }

      final file = File(
        '${chosenDir.path}${Platform.pathSeparator}$_downloadingName',
      );
      final sink = file.openWrite();

      int received = 0;
      final completer = Completer<void>();
      final subscription = streamed.stream.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            final prog = received / total;
            _downloadProgressNotifier.value = prog;
          }
        },
        onDone: () async {
          await sink.close();
          completer.complete();
        },
        onError: (e) async {
          await sink.close();
          completer.completeError(e);
        },
        cancelOnError: true,
      );

      // Await completion or cancellation
      await completer.future;
      await subscription.cancel();

      _downloadProgressNotifier.value = 1.0;

      // Run or open the downloaded file
      if (Platform.isWindows && file.path.toLowerCase().endsWith('.exe')) {
        // On Windows try to launch the installer via the shell so UAC / associated
        // handlers work correctly. Use runInShell and provide robust fallbacks.
        bool launched = false;
        try {
          final proc = await Process.start(file.path, [], runInShell: true);
          launched = true;
          await proc.exitCode;
          // delete the installer to avoid keeping many .exe files
          try {
            await file.delete();
          } catch (_) {}
        } catch (e) {
          // Fallback: try launching through cmd "start" which tends to be reliable
          try {
            await Process.run('cmd', [
              '/c',
              'start',
              '',
              file.path,
            ], runInShell: true);
            launched = true;
          } catch (e2) {
            // Last resort: try opening with OpenFilex
            try {
              await OpenFilex.open(file.path);
              launched = true;
            } catch (e3) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error al ejecutar el instalador: $e3'),
                  ),
                );
              }
            }
          }

          if (!launched && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al ejecutar el instalador: $e')),
            );
          }
        }
      } else {
        // Try to open using platform default handler (e.g., APK installer on Android)
        try {
          await OpenFilex.open(file.path);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al abrir el archivo: $e')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error en la descarga: $e')));
      }
    } finally {
      try {
        _activeDownloadClient?.close();
      } catch (_) {}
      _activeDownloadClient = null;
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadingName = null;
        });
      }
      _downloadingNotifier.value = false;
      _downloadProgressNotifier.value = 0.0;
      _downloadingNameNotifier.value = null;
    }
  }

  void _cancelDownload() {
    try {
      _activeDownloadClient?.close();
    } catch (_) {}
    _activeDownloadClient = null;
    if (mounted) {
      setState(() {
        _downloading = false;
        _downloadingName = null;
      });
    }
    _downloadingNotifier.value = false;
    _downloadProgressNotifier.value = 0.0;
    _downloadingNameNotifier.value = null;
  }

  bool get _updateAvailable {
    if (_serverVersion == null) return false;
    if (_clientVersion == null) {
      return true; // unknown client -> consider update available
    }
    return _serverVersion != _clientVersion;
  }

  Widget _buildUpdatesCard(ThemeData theme, ColorScheme colorScheme) {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 520;
    // Compact UI: small chip + version. Tap to open full details dialog.
    return InkWell(
      onTap: () => _showUpdatesDialog(context),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          Chip(
            label: Text(
              _updateError
                  ? 'Actualizaciones'
                  : (_updateAvailable ? 'Actualizar' : 'Al día'),
            ),
            backgroundColor: _updateError
                ? Colors.grey.shade700
                : (_updateAvailable
                      ? Colors.amber.shade700
                      : Colors.green.shade600),
            labelStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_serverVersion != null)
            Text(
              'v${_serverVersion!}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tight(
              Size(isCompact ? 30 : 36, isCompact ? 30 : 36),
            ),
            icon: Icon(
              Icons.info_outline,
              size: isCompact ? 18 : 20,
              color: _updatesHover ? colorScheme.primary : null,
            ),
            onPressed: () => _showUpdatesDialog(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showUpdatesDialog(BuildContext ctx) async {
    final theme = Theme.of(ctx);
    await showDialog<void>(
      context: ctx,
      barrierDismissible: !(Platform.isIOS || Platform.isMacOS),
      builder: (dctx) {
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Row(
            children: [
              const Expanded(
                child: Text(
                  'Actualizaciones',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (_updatesLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (Platform.isIOS || Platform.isMacOS) ...[
                  const Center(
                    child: Icon(
                      Icons.new_releases,
                      size: 48,
                      color: Colors.amber,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Nueva versión disponible',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Por favor, abre la aplicación TestFlight para instalar la última versión de Granite.',
                    textAlign: TextAlign.center,
                  ),
                ] else ...[
                  if (_serverVersion != null)
                    Text(
                      _clientVersion != null
                          ? 'Tú: ${_clientVersion!}  ·  Servidor: ${_serverVersion!}'
                          : 'Servidor: ${_serverVersion!}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(height: 8),
                  if (_cambiosText != null) Text(_cambiosText!),
                ],
                const SizedBox(height: 12),

                // Download progress via notifiers
                ValueListenableBuilder<bool>(
                  valueListenable: _downloadingNotifier,
                  builder: (context, downloading, _) {
                    if (!downloading) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ValueListenableBuilder<double>(
                          valueListenable: _downloadProgressNotifier,
                          builder: (context, p, _) =>
                              LinearProgressIndicator(value: p > 0 ? p : null),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ValueListenableBuilder<String?>(
                              valueListenable: _downloadingNameNotifier,
                              builder: (context, name, _) => Expanded(
                                child: Text(name ?? 'Descargando...'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ValueListenableBuilder<double>(
                              valueListenable: _downloadProgressNotifier,
                              builder: (context, p, _) =>
                                  Text('${(p * 100).toStringAsFixed(0)}%'),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            if (Platform.isIOS || Platform.isMacOS)
              ElevatedButton(
                onPressed: () {
                  // This opens the TestFlight app directly or the browser if not installed
                  // Replace YOUR_APP_ID with the actual ID from App Store Connect (e.g. 647xxxxxx)
                  const appId = '6470000000'; // <--- CAMBIA ESTO CON TU ID DE APPLE
                  launchUrl(
                    Uri.parse('https://testflight.apple.com/join/$appId'),
                    mode: LaunchMode.externalApplication,
                  );
                },
                child: const Text('Abrir TestFlight'),
              ),
            ValueListenableBuilder<bool>(
              valueListenable: _downloadingNotifier,
              builder: (context, downloading, _) {
                if (downloading) {
                  return TextButton(
                    onPressed: _cancelDownload,
                    child: const Text('Cancelar descarga'),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            if (!(Platform.isIOS || Platform.isMacOS))
              TextButton(
                onPressed: () => Navigator.of(dctx).pop(),
                child: const Text('Cerrar'),
              ),
            if (!(Platform.isIOS || Platform.isMacOS) &&
                !_updatesLoading &&
                _updateAvailable &&
                _patchUrl != null)
              TextButton(
                onPressed: () {
                  _startDownload(_patchUrl!);
                },
                child: const Text('Descargar Parche'),
              ),
            if (!(Platform.isIOS || Platform.isMacOS) &&
                !_updatesLoading &&
                _updateAvailable &&
                _descargaUrl != null)
              ElevatedButton(
                onPressed: () {
                  _startDownload(_descargaUrl!);
                },
                child: const Text('Descargar Instalador'),
              ),
          ],
        );
      },
    );
  }

  Future<void> _loadSavedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_savedUsernameKey);
    if (saved != null && saved.isNotEmpty) {
      setState(() {
        _usernameController.text = saved;
        _remember = true;
      });
    }
  }

  Future<void> _onLoginPressed() async {
    // Clear previous inline errors
    setState(() {
      _usernameError = null;
      _passwordError = null;
    });

    // Block login if update is available
    if (_updateAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe actualizar la aplicación para continuar.'),
          backgroundColor: Colors.amber,
        ),
      );
      _showUpdatesDialog(context);
      return;
    }

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        if (username.isEmpty) _usernameError = 'Usuario requerido';
        if (password.isEmpty) _passwordError = 'Contraseña requerida';
      });
      return;
    }

    setState(() => _loading = true);

    final apiService = Provider.of<ApiService>(context, listen: false);
    final res = await apiService.login(
      username,
      password,
      persistRefresh: _remember,
      persistCookies: _remember,
    );

    if (!mounted) return;

    setState(() => _loading = false);

    if (!res.ok) {
      // Try to show server-provided message if available
      String? msg;
      try {
        if (res.body is Map) {
          msg = (res.body['detail'] ?? res.body['message'] ?? res.body['error'])
              ?.toString();
        }
      } catch (_) {}
      msg ??=
          res.error ?? 'Error de inicio de sesión (estado ${res.statusCode})';

      // If 401/403, show password-level error; otherwise global
      if (res.statusCode == 401) {
        setState(() => _passwordError = 'Contraseña o usuario Invalido');
      } else if (res.statusCode == 403) {
        setState(() => _passwordError = msg);
      } else {
        // Show global errors as a SnackBar for immediate feedback.
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
      return;
    }

    // Save username preference
    final prefs = await SharedPreferences.getInstance();
    if (_remember) {
      await prefs.setString(_savedUsernameKey, username);
    } else {
      await prefs.remove(_savedUsernameKey);
    }

    // Try to fetch user info from the shared client
    final me = await apiService.client.me();
    String display = username;
    String? nombre;
    String role = 'Usuario';
    if (me.ok && me.body != null) {
      try {
        if (me.body is Map) {
          final Map mb = me.body as Map;
          if (mb['username'] != null) display = mb['username'].toString();
          // Try various common name fields; prefer Spanish 'nombre'
          if (mb['nombre'] != null) {
            nombre = mb['nombre'].toString();
          } else if (mb['first_name'] != null)
            nombre = mb['first_name'].toString();
          else if (mb['firstName'] != null)
            nombre = mb['firstName'].toString();
          else if (mb['name'] != null) {
            final s = mb['name'].toString();
            nombre = s.split(' ').first;
          }
          // role - try common fields
          if (mb['role'] != null) {
            role = mb['role'].toString();
          } else if (mb['roles'] != null &&
              mb['roles'] is List &&
              (mb['roles'] as List).isNotEmpty)
            role = (mb['roles'] as List).first.toString();
          else if (mb['groups'] != null &&
              mb['groups'] is List &&
              (mb['groups'] as List).isNotEmpty)
            role = (mb['groups'] as List).first.toString();
        }
      } catch (_) {}
    }

    if (!mounted) return;
    // Build User model and navigate to dashboard with it
    final user = User(username: display, role: role, nombre: nombre);
    // Store the user in ApiService so named-route navigation and sidebars
    // can access the current user without needing the object passed everywhere.
    try {
      apiService.setCurrentUser(user);
    } catch (_) {}
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => DashboardScreen(user: user),
        transitionDuration: const Duration(milliseconds: 1200),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.1, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    // Session listeners are handled globally by SessionWatcher in main.dart
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.of(context).size;
    final isPhone = size.width < 600;
    final isSmallPhone = size.width < 420;
    final horizontalPadding = isSmallPhone ? 16.0 : (isPhone ? 20.0 : 28.0);
    final verticalPadding = isPhone ? 20.0 : 40.0;
    final cardHorizontalPadding = isSmallPhone ? 16.0 : (isPhone ? 22.0 : 40.0);
    final cardVerticalPadding = isSmallPhone ? 18.0 : (isPhone ? 24.0 : 40.0);
    final titleSize = isSmallPhone ? 34.0 : (isPhone ? 40.0 : 48.0);
    final brandLetterSpacing = isSmallPhone ? 5.0 : (isPhone ? 6.5 : 8.0);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          AnimatedBackground(),
          // Keyboard listener for CapsLock hint (platform dependent)
          RawKeyboardListener(
            focusNode: _keyboardFocus,
            onKey: (event) {
              if (event.logicalKey == LogicalKeyboardKey.capsLock &&
                  event is RawKeyDownEvent) {
                setState(() => _capsLock = !_capsLock);
              }
            },
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Lottie header (optional)
                      SizedBox(
                        height: isPhone ? 56 : 84,
                        child: Center(
                          child: Builder(
                            builder: (context) {
                              // Empty builder to maintain layout space if needed, or remove SizedBox if not.
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Title
                      _GraniteProfessionalTitle(
                        text: 'ConfigTool',
                        fontSize: titleSize,
                      ),
                      const SizedBox(height: 8),
                      // Subtext with wide tracking for premium feel
                      Text(
                        'GRANITE',
                        style: TextStyle(
                          color: colorScheme.primary.withValues(alpha: 0.9),
                          fontSize: isPhone ? 12 : 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: brandLetterSpacing, // Wide spacing
                        ),
                      ),
                      SizedBox(height: isPhone ? 18 : 28),

                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isPhone ? 520 : 760,
                        ),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: cardHorizontalPadding,
                            vertical: cardVerticalPadding,
                          ),
                          decoration: BoxDecoration(
                            color: theme.brightness == Brightness.dark
                                ? Colors.black.withOpacity(0.3)
                                : Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(
                                theme.brightness == Brightness.dark
                                    ? 0.05
                                    : 0.2,
                              ),
                              width: 0.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Username
                                  TextField(
                                    focusNode: _usernameFocus,
                                    controller: _usernameController,
                                    textAlign: TextAlign.start,
                                    style: TextStyle(
                                      color: theme.textTheme.bodyLarge?.color,
                                      fontSize: 14,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Usuario',
                                      hintStyle: TextStyle(
                                        color: theme.textTheme.bodyMedium?.color
                                            ?.withOpacity(0.5),
                                        fontSize: 14,
                                      ),
                                      filled: true,
                                      fillColor:
                                          theme.brightness == Brightness.dark
                                          ? Colors.white.withOpacity(0.1)
                                          : Colors.white.withOpacity(0.5),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Colors.transparent,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: colorScheme.primary
                                              .withOpacity(0.5),
                                          width: 1,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                    ),
                                    textInputAction: TextInputAction.next,
                                    onSubmitted: (_) =>
                                        _passwordFocus.requestFocus(),
                                  ),
                                  if (_usernameError != null) ...[
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        _usernameError!,
                                        style: TextStyle(
                                          color: colorScheme.error,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),

                                  // Password with visibility
                                  TextField(
                                    focusNode: _passwordFocus,
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    textAlign: TextAlign.start,
                                    style: TextStyle(
                                      color: theme.textTheme.bodyLarge?.color,
                                      fontSize: 14,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Contraseña',
                                      hintStyle: TextStyle(
                                        color: theme.textTheme.bodyMedium?.color
                                            ?.withOpacity(0.5),
                                        fontSize: 14,
                                      ),
                                      filled: true,
                                      fillColor:
                                          theme.brightness == Brightness.dark
                                          ? Colors.white.withOpacity(0.1)
                                          : Colors.white.withOpacity(0.5),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Colors.transparent,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: colorScheme.primary
                                              .withOpacity(0.5),
                                          width: 1,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                      suffixIcon: IconButton(
                                        iconSize: 18,
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off_rounded
                                              : Icons.visibility_rounded,
                                          color: theme
                                              .textTheme
                                              .bodyMedium
                                              ?.color
                                              ?.withOpacity(0.4),
                                        ),
                                        onPressed: () => setState(
                                          () => _obscurePassword =
                                              !_obscurePassword,
                                        ),
                                        tooltip: _obscurePassword
                                            ? 'Mostrar contraseña'
                                            : 'Ocultar contraseña',
                                      ),
                                    ),
                                    onSubmitted: (_) {
                                      if (!_loading) _onLoginPressed();
                                    },
                                  ),
                                  if (_capsLock) ...[
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Bloq Mayús activado',
                                        style: TextStyle(
                                          color: Colors.amber.shade700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (_passwordError != null) ...[
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        _passwordError!,
                                        style: TextStyle(
                                          color: colorScheme.error,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),

                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Checkbox(
                                            value: _remember,
                                            onChanged: (v) => setState(
                                              () => _remember = v ?? false,
                                            ),
                                            activeColor: colorScheme.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () => setState(
                                                () => _remember = !_remember,
                                              ),
                                              child: Text(
                                                'Recordar usuario',
                                                style: TextStyle(
                                                  color: theme
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.color
                                                      ?.withOpacity(0.9),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: () => showDialog<void>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              backgroundColor: theme.cardColor,
                                              title: Text(
                                                '¿Olvidaste tu contraseña?',
                                                style: TextStyle(
                                                  color: theme
                                                      .textTheme
                                                      .titleLarge
                                                      ?.color,
                                                ),
                                              ),
                                              content: const Text(
                                                'El restablecimiento de contraseña se gestiona en el servidor.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.of(ctx).pop(),
                                                  child: const Text('Cerrar'),
                                                ),
                                              ],
                                            ),
                                          ),
                                          child: Text(
                                            '¿Olvidaste tu contraseña?',
                                            style: TextStyle(
                                              fontSize: isPhone ? 12 : null,
                                              color: theme
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.color
                                                  ?.withOpacity(0.9),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 8),

                                  // Login or Update button
                                  Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 420,
                                      ),
                                      child: Container(
                                        height: isPhone
                                            ? 42
                                            : 38, // Standard macOS button height
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors:
                                                _updateAvailable &&
                                                    !_updateError
                                                ? [
                                                    Colors.amber.shade700,
                                                    Colors.amber.shade800,
                                                  ]
                                                : [
                                                    colorScheme.primary,
                                                    Color.lerp(
                                                      colorScheme.primary,
                                                      Colors.black,
                                                      0.2,
                                                    )!,
                                                  ],
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.2,
                                              ),
                                              offset: const Offset(0, 1),
                                              blurRadius: 2,
                                            ),
                                          ],
                                        ),
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 0,
                                              horizontal: 24,
                                            ),
                                          ),
                                          onPressed: _loading
                                              ? null
                                              : (_updateAvailable &&
                                                        !_updateError
                                                    ? () => _showUpdatesDialog(
                                                        context,
                                                      )
                                                    : _onLoginPressed),
                                          child: _loading
                                              ? const SizedBox(
                                                  height: 18,
                                                  width: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : Text(
                                                  _updateAvailable &&
                                                          !_updateError
                                                      ? 'Actualización Requerida'
                                                      : 'Iniciar Sesión',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    letterSpacing:
                                                        -0.2, // macOS tight tracking
                                                  ),
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
                      ),

                      SizedBox(height: isPhone ? 12 : 18),
                      // Updates area integrated into main view logic now
                      if (_updateError) _buildUpdatesCard(theme, colorScheme),
                    ],
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

/// A professional, clean gradient title with subtle glow.
class _GraniteProfessionalTitle extends StatelessWidget {
  final String text;
  final double fontSize;

  const _GraniteProfessionalTitle({
    required this.text,
    this.fontSize = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: -1.0, // Tight, modern tracking
        // Metallic/Silver Gradient
        foreground: Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFE3E3E3), Color(0xFFF5F5F5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(const Rect.fromLTWH(0, 0, 300, 100)),
        shadows: [
          // Soft ambient brand glow (simulated with white/silver here since text is white)
          // Actually, let's use a subtle drop shadow to lift it off the BG
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          // Slight crisp outline shadow
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}
