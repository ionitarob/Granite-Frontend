import 'package:flutter/material.dart';
import 'services/notification_provider.dart';
import 'services/xiaomi_provider.dart';
import 'widgets/notification_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'splash_screen.dart';
import 'dart:io';
import 'debug_http_override.dart';
import 'services/theme_controller.dart';
import 'services/api_service.dart';
import 'config.dart';
import 'services/orderops_service.dart';
import 'dashboard_screen.dart';
import 'screens/amazon/amazon_grading_screen.dart';
import 'screens/amazon/amazon_proyectos_dashboard.dart';
import 'screens/amazon/amazon_batch_registration.dart';
import 'screens/amazon/sorting_screen.dart';
import 'screens/amazon/amz_close_box_screen.dart';
import 'screens/amazon/amz_find_box_screen.dart';
import 'screens/amazon/amz_find_dsn_screen.dart';
import 'screens/amazon/transfers_upload_screen.dart';
import 'screens/amazon/recogida_ops_page.dart';
import 'screens/amazon/quality_index.dart';
import 'screens/amazon/au_laser_form.dart';
import 'screens/amazon/asin_flip_form.dart';
import 'screens/amazon/unsellable_grading_form.dart';
import 'screens/amazon/inventory_control_screen.dart';
import 'screens/amazon/picking_screen.dart';
import 'screens/amazon/receiving_screen.dart';
import 'screens/amazon/icqa_screen.dart';
import 'login_screen.dart';
import 'screens/igualdad/entrada_stock_new.dart';
import 'screens/igualdad/igualdad_dashboard.dart';
import 'screens/igualdad/registro_smartphone.dart';
import 'screens/igualdad/registro_pulsera.dart';
import 'screens/igualdad/registro_powerbank.dart';
import 'screens/igualdad/registro_boton.dart';
import 'screens/igualdad/historial_expediciones.dart';
import 'screens/igualdad/cerrar_idim_oysta.dart';
import 'screens/serials/serial_link.dart';
import 'screens/serials/serial_change.dart';
import 'screens/serials/serial_label_generator.dart';
import 'screens/serials/masks_screen.dart';
import 'screens/serials/historial_cambios_serial.dart';
import 'screens/serials/historial_match_unidad.dart';
import 'screens/serials/serial_verification_screen.dart';
import 'screens/servers/registro_previ_screen.dart';
import 'screens/servers/registro_servidor_screen.dart';
import 'screens/rrhh/alta_empleado.dart';
import 'screens/rrhh/fichaje_screen.dart';
import 'screens/rrhh/gestion_usuarios_screen.dart';
import 'screens/rrhh/job_selector.dart';
import 'screens/rrhh/registro_fichaje_screen.dart';
import 'screens/xiaomi/xiaomi_historial.dart';
import 'screens/xiaomi/xiaomi_registro_orden.dart';
import 'screens/xiaomi/cerrar_cesb.dart';
import 'screens/xiaomi/xiaomi_estadisticas.dart';
import 'screens/analisis_y_serveis/ays_dashboard.dart';
import 'screens/analisis_y_serveis/ays_management_screen.dart';
import 'screens/sentinel_for_imaging/active_images_screen.dart';
import 'screens/sentinel_for_imaging/physical_tables_screen.dart';
import 'screens/sentinel_for_imaging/sentinel_provider.dart';
import 'screens/sentinel_for_imaging/sentinel_stats_screen.dart';
import 'screens/orderops/order_queue_screen.dart';
import 'screens/orderops/work_items_screen.dart';
import 'screens/orderops/agent_activity_screen.dart';
import 'screens/orderops/agent_memory_screen.dart';
import 'screens/orderops/cotizaciones_management_screen.dart';
import 'screens/orderops/proyectos_management_screen.dart';
import 'screens/orderops/serigrafia_repository_screen.dart';
import 'screens/tv/tv_revision_screen.dart';
import 'screens/tv/tv_history_screen.dart';
import 'widgets/main_sidebar.dart';
import 'services/navigation_tracker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeDateFormatting('es');
  } catch (_) {
    // If the locale data fails to initialize we still continue with defaults.
  }
  // Install a debug-only HttpOverrides that accepts self-signed certificates
  // for the configured backend host. This affects WebSocket.connect and
  // any code that uses `dart:io` HttpClient (including package:http's
  // default IOClient), so the whole app can connect to dev servers with
  // self-signed certs while running in debug mode.
  if (kDebugMode) {
    try {
      final host = Uri.parse(kBackendBaseUrl).host;
      HttpOverrides.global = DevHttpOverrides([host]);
    } catch (_) {
      // Parsing failed or other issue — fall back to no overrides.
    }
  }

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>(
          create: (_) => ThemeController(),
        ),
        ChangeNotifierProvider<ApiService>(
          create: (_) => ApiService(
            // In debug builds allow connecting to dev backends with
            // self-signed certs for the configured backend host.
            allowBadCertificateForHosts: kDebugMode
                ? [Uri.parse(kBackendBaseUrl).host]
                : null,
          ),
        ),
        ChangeNotifierProvider<SentinelProvider>(
          create: (_) => SentinelProvider(),
        ),
        ChangeNotifierProxyProvider<ApiService, NotificationProvider>(
          create: (ctx) => NotificationProvider(
            apiService: Provider.of<ApiService>(ctx, listen: false),
          ),
          update: (ctx, api, previous) => previous ?? NotificationProvider(apiService: api),
        ),
        ChangeNotifierProxyProvider<ApiService, XiaomiProvider>(
          create: (ctx) => XiaomiProvider(
            apiService: Provider.of<ApiService>(ctx, listen: false),
          ),
          update: (ctx, api, previous) => previous ?? XiaomiProvider(apiService: api),
        ),
        ProxyProvider<ApiService, OrderOpsService>(
          update: (ctx, api, previous) => previous ?? OrderOpsService(api.client),
        ),
      ],
      child: Consumer<ThemeController>(
        builder: (context, themeCtrl, _) {
          final dark = themeCtrl.isDark;
          final lightTheme = ThemeData(
            brightness: Brightness.light,
            primaryColor: Colors.red.shade700,
            scaffoldBackgroundColor: Colors.white,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.red,
              brightness: Brightness.light,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0,
            ),
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: _FadePageTransitionsBuilder(),
                TargetPlatform.iOS: _FadePageTransitionsBuilder(),
                TargetPlatform.macOS: _FadePageTransitionsBuilder(),
                TargetPlatform.windows: _FadePageTransitionsBuilder(),
                TargetPlatform.linux: _FadePageTransitionsBuilder(),
                TargetPlatform.fuchsia: _FadePageTransitionsBuilder(),
              },
            ),
          );

          final darkTheme = ThemeData(
            brightness: Brightness.dark,
            primaryColor: Colors.red.shade700,
            scaffoldBackgroundColor: Colors.black,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.red,
              brightness: Brightness.dark,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: _FadePageTransitionsBuilder(),
                TargetPlatform.iOS: _FadePageTransitionsBuilder(),
                TargetPlatform.macOS: _FadePageTransitionsBuilder(),
                TargetPlatform.windows: _FadePageTransitionsBuilder(),
                TargetPlatform.linux: _FadePageTransitionsBuilder(),
                TargetPlatform.fuchsia: _FadePageTransitionsBuilder(),
              },
            ),
          );

          // Provide a global scaffold messenger and navigator key so we can show
          // session expiry SnackBars and dialogs from anywhere in the app.
          return SessionWatcher(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: const SplashScreen(),
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              routes: {
                // Igualdad
                '/igualdad/entrada': (_) => const EntradaStockNewScreen(),
                '/igualdad/dashboard': (_) => const IgualdadDashboard(),
                '/igualdad/registro/smartphone': (_) =>
                    const RegistroSmartphoneScreen(),
                '/igualdad/registro/pulsera': (_) =>
                    const RegistroPulseraScreen(),
                '/igualdad/registro/powerbank': (_) =>
                    const RegistroPowerbankScreen(),
                '/igualdad/registro/boton': (_) => const RegistroBotonScreen(),
                '/igualdad/historial': (_) =>
                    const HistorialExpedicionesScreen(),
                '/igualdad/cerrar': (_) => const CerrarIdimOystaScreen(),
                '/dashboard': (_) => const DashboardScreen(),
                '/dashboard/redesigned': (_) => const DashboardScreen(),
                '/analisis/dashboard': (_) => const AysDashboard(),
                '/analisis/management': (_) => const AysManagementScreen(),
                // Quality forms
                '/amazon/quality': (_) => const QualityIndex(),
                '/amazon/quality/au_laser': (_) => const AuLaserForm(),
                '/amazon/quality/asin_flip': (_) => const AsinFlipForm(),
                '/amazon/quality/unsellable': (_) =>
                    const UnsellableGradingForm(),
                // Amazon grading and tools (wired from the main sidebar)
                '/amazon/proyectos': (_) => const AmazonProyectosDashboard(),
                '/amazon/proyectos/batch/registration': (context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  return AmazonBatchRegistration(batch: args);
                },
                '/amazon/grading': (_) => const AmazonGradingScreen(),
                '/amazon/sorting': (_) => const SortingScreen(),
                '/amazon/herramientas/closebox': (_) =>
                    const AmzCloseBoxScreen(),
                '/amazon/herramientas/findbox': (_) => const AmzFindBoxScreen(),
                '/amazon/herramientas/finddsn': (_) => const AmzFindDsnScreen(),
                '/amazon/transfers': (_) => const TransfersUploadScreen(),
                '/amazon/recogida_ops': (_) => const RecogidaOpsPage(),
                '/amazon/inventory': (_) => const InventoryControlScreen(),
                '/amazon/inventory/picking': (_) => const ProductPickScreen(),
                '/amazon/inventory/receiving': (_) => const ReceivingScreen(),
                '/amazon/inventory/icqa': (_) => const ICQAScreen(),
                '/serials/match': (_) => const SerialLinkScreen(),
                '/serials/verification': (_) => const SerialVerificationScreen(),
                '/serials/match-history': (_) => const HistorialMatchUnidadScreen(),
                '/serials/serial-change': (_) => const SerialChangeScreen(),
                '/serials/labels': (_) => const SerialLabelGeneratorScreen(),
                '/serials/serial-changes': (_) =>
                    const HistorialCambiosSerialScreen(),
                '/serials/masks': (_) => const MasksScreen(),
                '/serials/repository': (_) => const SerigrafiaRepositoryScreen(),
                '/automatizations/cambio_serial': (_) =>
                    const SerialLinkScreen(),
                '/servers/previ': (_) => const RegistroPreviScreen(),
                '/servers/servidores': (_) => const RegistroServidorScreen(),
                // Xiaomi
                '/xiaomi/historial': (_) => const XiaomiHistoricoPage(),
                '/xiaomi/registro/unidades': (_) =>
                    const XiaomiRegistroOrdenScreen(),
                '/xiaomi/cerrar_cesb': (_) => const CerrarCesbScreen(),
                '/xiaomi/estadisticas': (_) => const XiaomiEstadisticasPage(),
                // Recursos Humanos
                '/hr/fichaje': (_) => const FichajeScreen(),
                '/hr/alta_empleado': (_) => const AltaEmpleadoScreen(),
                '/hr/registro_fichaje': (_) => const RegistroFichajeScreen(),
                '/hr/asignacion_trabajo': (_) => const JobSelectorScreen(),
                '/hr/gestion_empleado': (_) => const GestionEmpleadosScreen(),
                // Sentinel
                '/sentinel/active': (_) => const ActiveImagesScreen(),
                '/sentinel/stats': (_) => const SentinelStatsScreen(),
                '/sentinel/tables': (context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  if (args is int) {
                    return PhysicalTablesScreen(orderId: args);
                  }
                  if (args is Map<String, dynamic> && args.containsKey('orderId')) {
                    return PhysicalTablesScreen(orderId: args['orderId']);
                  }
                  return const PhysicalTablesScreen();
                },
                // OrderOps AI
                '/orderops/queue': (_) => const OrderQueueScreen(),
                '/orderops/work-items': (_) => const WorkItemsScreen(),
                '/orderops/activity': (_) => const AgentActivityScreen(),
                '/orderops/memory': (_) => const AgentMemoryScreen(),
                '/orderops/cotizaciones': (_) => const CotizacionesManagementScreen(),
                '/orderops/proyectos': (_) => const ProyectosManagementScreen(),
                '/tv/revision': (_) => const TvRevisionScreen(),
                '/tv/history': (_) => const TvHistoryScreen(),
              },
            ),
          );
        },
      ),
    );
  }
}

// Global keys so session notifications can be shown from non-visual code
final GlobalKey<ScaffoldMessengerState> globalScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

/// SessionWatcher listens to `ApiService` and shows global SnackBars/dialogs
/// when the session is about to expire or has expired. It should wrap the
/// MaterialApp so the SnackBar and dialogs are shown above all routes.
class SessionWatcher extends StatefulWidget {
  final Widget child;
  const SessionWatcher({required this.child, super.key});

  @override
  State<SessionWatcher> createState() => _SessionWatcherState();
}

class _SessionWatcherState extends State<SessionWatcher>
    with WidgetsBindingObserver {
  ApiService? _apiService;
  bool _handlingForcedLogout = false;
  final ValueNotifier<bool> _mobileDockHidden = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final svc = Provider.of<ApiService>(context, listen: false);
    if (_apiService != svc) {
      _apiService?.sessionExpiring.removeListener(_onSessionExpiring);
      _apiService?.sessionExpired.removeListener(_onSessionExpired);
      _apiService = svc;
      _apiService?.sessionExpiring.addListener(_onSessionExpiring);
      _apiService?.sessionExpired.addListener(_onSessionExpired);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (!_mobileDockHidden.value) {
        _mobileDockHidden.value = true;
      }
      return;
    }

    if (state == AppLifecycleState.resumed) {
      if (_mobileDockHidden.value) {
        _mobileDockHidden.value = false;
      }
    }
  }

  void _onSessionExpiring() {
    try {
      if (_apiService?.sessionExpiring.value ?? false) {
        globalScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: const Text('Your session will expire soon.'),
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Refresh',
              onPressed: () async {
                await _apiService?.refreshAccessToken();
              },
            ),
          ),
        );
      }
    } catch (_) {}
  }

  void _onSessionExpired() async {
    final svc = _apiService;
    if (svc == null) return;
    if (!svc.sessionExpired.value) return;
    if (_handlingForcedLogout) return;
    _handlingForcedLogout = true;
    try {
      final message = svc.forcedLogoutMessage;
      final messenger = globalScaffoldMessengerKey.currentState;
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
      );

      await svc.performForcedLogout();

      final navigator = globalNavigatorKey.currentState;
      if (navigator != null) {
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (_) {
    } finally {
      _handlingForcedLogout = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _apiService?.sessionExpiring.removeListener(_onSessionExpiring);
    _apiService?.sessionExpired.removeListener(_onSessionExpired);
    _mobileDockHidden.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Inject global keys into MaterialApp via builder pattern by wrapping the
    // provided child; the child is expected to be a MaterialApp instance.
    return Builder(
      builder: (ctx) {
        if (widget.child is MaterialApp) {
          final app = widget.child as MaterialApp;
          final routeBuilders = app.routes ?? <String, WidgetBuilder>{};
          return MaterialApp(
            key: app.key,
            scaffoldMessengerKey: globalScaffoldMessengerKey,
            navigatorKey: globalNavigatorKey,
            title: app.title,
            theme: app.theme,
            darkTheme: app.darkTheme,
            themeMode: app.themeMode,
            debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
            home: app.home,
            routes: routeBuilders,
            onGenerateRoute: (settings) {
              final args = settings.arguments;
              final noTransition =
                  args is Map && (args['noTransition'] == true);
              if (!noTransition) return null;

              final builder = routeBuilders[settings.name];
              if (builder == null) return null;

              return PageRouteBuilder(
                settings: settings,
                pageBuilder: (ctx, _, __) => builder(ctx),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              );
            },
            navigatorObservers: [appRouteTracker],
            builder: (context, child) {
              final builtChild = app.builder != null
                  ? app.builder!(context, child)
                  : child ?? const SizedBox.shrink();
              final media = MediaQuery.of(context);
              final width = media.size.width;
              final isDockDevice = width < 900;
              final reserveDockSpace = (isDockDevice && media.viewInsets.bottom == 0)
                  ? (width < 430 ? 52.0 : 60.0)
                  : 0.0;
              final insetChild = MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(
                    bottom: media.padding.bottom + reserveDockSpace,
                  ),
                  viewPadding: media.viewPadding.copyWith(
                    bottom: media.viewPadding.bottom + reserveDockSpace,
                  ),
                ),
                child: builtChild,
              );
              return NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  final vertical = notification.metrics.axis == Axis.vertical;
                  if (!vertical) return false;

                  if (notification is ScrollUpdateNotification ||
                      notification is OverscrollNotification) {
                    if (!_mobileDockHidden.value) {
                      _mobileDockHidden.value = true;
                    }
                  } else if (notification is ScrollEndNotification) {
                    if (_mobileDockHidden.value) {
                      _mobileDockHidden.value = false;
                    }
                  } else if (notification is UserScrollNotification &&
                      notification.direction == ScrollDirection.idle) {
                    if (_mobileDockHidden.value) {
                      _mobileDockHidden.value = false;
                    }
                  }
                  return false;
                },
                child: Stack(
                  children: [
                    insetChild,
                    GlobalMobileSidebarDock(
                      rootNavigatorKey: globalNavigatorKey,
                      hiddenListenable: _mobileDockHidden,
                    ),
                    const NotificationBar(),
                  ],
                ),
              );
            },
          );
        }
        return widget.child;
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ConfigTool Granite')),
      body: const Center(child: Text('Hello World!')),
    );
  }
}

class _FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: child,
    );
  }
}
