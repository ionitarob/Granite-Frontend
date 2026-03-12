import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import '../services/theme_controller.dart';
import '../models/user_model.dart';
import 'package:flutter/scheduler.dart';
import '../services/api_service.dart';
import '../login_screen.dart';

/// A reusable main sidebar widget that can be embedded (permanent) or shown
/// as an overlay via [showAppSidebar]. It mirrors the sidebar used in the
/// redesigned dashboard so screens can open the same navigation anywhere.
class MainSidebar extends StatefulWidget {
  final User? user;
  final bool permanent; // when true, renders the fixed-width container
  final String? currentRoute;
  const MainSidebar({
    super.key,
    this.user,
    this.permanent = true,
    this.currentRoute,
  });

  @override
  State<MainSidebar> createState() => _MainSidebarState();
}

class _MainSidebarState extends State<MainSidebar> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final permanent = widget.permanent;
    ThemeController? theme;
    try {
      theme = Provider.of<ThemeController>(context);
    } catch (_) {
      theme = null;
    }
    final isDark = theme?.isDark ?? true;
    final routeName =
        widget.currentRoute ?? ModalRoute.of(context)?.settings.name;
    final logoAsset = 'lib/assets/logo.png';

    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textMuted = isDark ? Colors.white70 : Colors.black54;
    final highlight = Theme.of(context).colorScheme.primary;

    final surface = AppleSidebarSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLogo(context, logoAsset, textPrimary, isDark),
          const SizedBox(height: 14),

          // Optional search (highly recommended)
          AppleSidebarSearch(
            hint: 'Search…',
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            onSubmitted: (q) {
              // optional: implement search/filter later
            },
          ),

          const SizedBox(height: 18),

          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(
                    context,
                    textPrimary,
                    textMuted,
                    routeName: routeName,
                    highlight: highlight,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 18),
                  if ([
                    'admin',
                    'clerc',
                    'chief',
                    'technitian',
                    'technician',
                  ].any(
                    (r) => (user?.role ?? '').toLowerCase().contains(r),
                  )) ...[
                    const SidebarSectionHeader(title: 'ADMIN'),
                    const SizedBox(height: 8),
                    SidebarExpansionTile(
                      title: 'Recursos Humanos',
                      icon: Icons.people_alt_rounded,
                      highlight: highlight,
                      textPrimary: textPrimary,
                      initiallyExpanded: [
                        '/hr/fichaje',
                        '/hr/alta_empleado',
                        '/hr/registro_fichaje',
                        '/hr/asignacion_trabajo',
                        '/hr/gestion_empleado',
                      ].contains(routeName),
                      children: [
                        _SidebarTile(
                          label: 'Fichaje',
                          icon: Icons.access_time_rounded,
                          selected: routeName == '/hr/fichaje',
                          onTap: () => _navigate(
                            context,
                            '/hr/fichaje',
                            closeOverlay: !permanent,
                          ),
                          highlight: highlight,
                          textPrimary: textPrimary,
                          isDark: isDark,
                        ),
                        _SidebarTile(
                          label: 'Alta Empleado',
                          icon: Icons.person_add_rounded,
                          selected: routeName == '/hr/alta_empleado',
                          onTap: () => _navigate(
                            context,
                            '/hr/alta_empleado',
                            closeOverlay: !permanent,
                          ),
                          highlight: highlight,
                          textPrimary: textPrimary,
                          isDark: isDark,
                        ),
                        _SidebarTile(
                          label: 'Registro Fichajes',
                          icon: Icons.format_list_bulleted_rounded,
                          selected: routeName == '/hr/registro_fichaje',
                          onTap: () => _navigate(
                            context,
                            '/hr/registro_fichaje',
                            closeOverlay: !permanent,
                          ),
                          highlight: highlight,
                          textPrimary: textPrimary,
                          isDark: isDark,
                        ),
                        _SidebarTile(
                          label: 'Asignación Trabajo',
                          icon: Icons.work_outline_rounded,
                          selected: routeName == '/hr/asignacion_trabajo',
                          onTap: () => _navigate(
                            context,
                            '/hr/asignacion_trabajo',
                            closeOverlay: !permanent,
                          ),
                          highlight: highlight,
                          textPrimary: textPrimary,
                          isDark: isDark,
                        ),
                        _SidebarTile(
                          label: 'Gestión Empleado',
                          icon: Icons.manage_accounts_rounded,
                          selected: routeName == '/hr/gestion_empleado',
                          onTap: () => _navigate(
                            context,
                            '/hr/gestion_empleado',
                            closeOverlay: !permanent,
                          ),
                          highlight: highlight,
                          textPrimary: textPrimary,
                          isDark: isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          Divider(height: 1, thickness: .6, color: textMuted.withOpacity(0.18)),
          const SizedBox(height: 12),
          _buildFooter(context, isDark, textPrimary, textMuted, logoAsset),
        ],
      ),
    );

    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320, minWidth: 240),
      child: SizedBox(width: 268, child: surface),
    );

    return permanent
        ? content
        : Material(type: MaterialType.transparency, child: content);
  }

  Widget _buildLogo(
    BuildContext context,
    String logoAsset,
    Color textPrimary,
    bool isDark,
  ) {
    final permanent = widget.permanent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (!permanent) {
            Navigator.of(context).pop();
          }
          SchedulerBinding.instance.addPostFrameCallback(
            (_) => Navigator.of(
              context,
              rootNavigator: true,
            ).pushNamed('/dashboard/redesigned'),
          );
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withOpacity(isDark ? 0.08 : 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.asset(
                logoAsset,
                height: 24,
                width: 24,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, st) =>
                    Icon(Icons.dashboard_rounded, color: textPrimary, size: 24),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'ConfigTool',
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 17,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    bool isDark,
    Color textPrimary,
    Color textMuted,
    String logoAsset,
  ) {
    final user = widget.user;
    return Column(
      children: [
        _SidebarTile(
          label: isDark ? 'Night Mode' : 'Bright Mode',
          icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_outlined,
          selected: false,
          onTap: () {
            try {
              Provider.of<ThemeController>(context, listen: false).toggle();
            } catch (_) {}
          },
          highlight: textPrimary,
          textPrimary: textPrimary,
          isDark: isDark,
          trailing: Switch.adaptive(
            value: isDark,
            onChanged: (v) {
              try {
                Provider.of<ThemeController>(context, listen: false).toggle();
              } catch (_) {}
            },
            activeColor: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.03)
                : Colors.black.withOpacity(0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.05),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.2),
                  child: Text(
                    (user?.displayName() ?? 'U')[0].toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName() ?? 'Usuario',
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      user?.role ?? 'Cuenta',
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.logout_rounded, color: textMuted, size: 20),
                onPressed: () => _handleLogout(context),
                tooltip: 'Cerrar sesión',
                style: IconButton.styleFrom(
                  backgroundColor: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.05),
                  hoverColor: Theme.of(
                    context,
                  ).colorScheme.error.withOpacity(0.1),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final client = api.client;
      await client.loadCookiesFromStorage();
      final res = await api.logout();
      navigator.pop();
      if (res.ok) {
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Logout failed: ${res.error ?? res.statusCode}'),
          ),
        );
      }
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('Logout error: $e')));
    }
  }

  void _navigate(
    BuildContext context,
    String route, {
    required bool closeOverlay,
  }) {
    if (closeOverlay) {
      Navigator.of(context).pop();
    }
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => Navigator.of(context, rootNavigator: true).pushNamed(route),
    );
  }

  Widget _buildSection(
    BuildContext context,
    Color textPrimary,
    Color textMuted, {
    required String? routeName,
    required Color highlight,
    required bool isDark,
  }) {
    final permanent = widget.permanent;
    final user = widget.user;
    if (_query.isNotEmpty) {
      final q = _query;

      final entries = <({String label, IconData icon, String route})>[
        // Amazon
        (
          label: 'Amazon · Grading',
          icon: Icons.grade_rounded,
          route: '/amazon/grading',
        ),
        (
          label: 'Amazon · Sorting',
          icon: Icons.sort_rounded,
          route: '/amazon/sorting',
        ),
        (
          label: 'Amazon · Quality Check',
          icon: Icons.search_off_rounded,
          route: '/amazon/quality',
        ),
        (
          label: 'Amazon · Inventory · Registro',
          icon: Icons.app_registration_rounded,
          route: '/amazon/inventory',
        ),
        (
          label: 'Amazon · Inventory · Picking',
          icon: Icons.shopping_cart_rounded,
          route: '/amazon/inventory/picking',
        ),
        (
          label: 'Amazon · Inventory · Receiving',
          icon: Icons.move_to_inbox_rounded,
          route: '/amazon/inventory/receiving',
        ),
        (
          label: 'Amazon · Inventory · ICQA',
          icon: Icons.check_circle_rounded,
          route: '/amazon/inventory/icqa',
        ),
        (
          label: 'Amazon · Herramientas · Cerrar Box',
          icon: Icons.close_rounded,
          route: '/amazon/herramientas/closebox',
        ),
        (
          label: 'Amazon · Herramientas · Buscar Box',
          icon: Icons.find_in_page_rounded,
          route: '/amazon/herramientas/findbox',
        ),
        (
          label: 'Amazon · Herramientas · Buscar DSN',
          icon: Icons.search_rounded,
          route: '/amazon/herramientas/finddsn',
        ),

        // OrderOps
        (
          label: 'OrderOps · Console / Queue',
          icon: Icons.list_alt_rounded,
          route: '/orderops/queue',
        ),
        (
          label: 'OrderOps · Work Items',
          icon: Icons.task_alt_rounded,
          route: '/orderops/work-items',
        ),
        (
          label: 'OrderOps · Activity Log',
          icon: Icons.history_edu_rounded,
          route: '/orderops/activity',
        ),
        (
          label: 'OrderOps · Agent Q/A',
          icon: Icons.question_answer_rounded,
          route: '/orderops/memory',
        ),

        // Igualdad
        (
          label: 'Igualdad · Dashboard',
          icon: Icons.dashboard_rounded,
          route: '/igualdad/dashboard',
        ),
        (
          label: 'Igualdad · Entrada Stock',
          icon: Icons.login_rounded,
          route: '/igualdad/entrada',
        ),
        (
          label: 'Igualdad · Registros · Smartphone',
          icon: Icons.smartphone_rounded,
          route: '/igualdad/registro/smartphone',
        ),
        (
          label: 'Igualdad · Registros · Pulsera',
          icon: Icons.watch_rounded,
          route: '/igualdad/registro/pulsera',
        ),
        (
          label: 'Igualdad · Registros · Powerbank',
          icon: Icons.battery_charging_full_rounded,
          route: '/igualdad/registro/powerbank',
        ),
        (
          label: 'Igualdad · Registros · Botón',
          icon: Icons.radio_button_checked_rounded,
          route: '/igualdad/registro/boton',
        ),
        (
          label: 'Igualdad · Historial',
          icon: Icons.history_rounded,
          route: '/igualdad/historial',
        ),

        // Serials
        (
          label: 'Serials · Registro Serial',
          icon: Icons.change_circle_rounded,
          route: '/serials/cambio',
        ),
        (
          label: 'Serials · Cambio Serial',
          icon: Icons.swap_horiz_rounded,
          route: '/serials/change',
        ),
        (
          label: 'Serials · Etiquetas',
          icon: Icons.label_rounded,
          route: '/serials/labels',
        ),
        (
          label: 'Serials · Máscaras',
          icon: Icons.masks_rounded,
          route: '/serials/masks',
        ),
        (
          label: 'Serials · Historial Cambios',
          icon: Icons.history_edu_rounded,
          route: '/serials/serial-changes',
        ),

        // Xiaomi
        (
          label: 'Xiaomi · Registro Unidades',
          icon: Icons.app_registration_rounded,
          route: '/xiaomi/registro/unidades',
        ),
        (
          label: 'Xiaomi · Cerrar CESB',
          icon: Icons.check_circle_outline_rounded,
          route: '/xiaomi/cerrar_cesb',
        ),
        (
          label: 'Xiaomi · Historial',
          icon: Icons.history_rounded,
          route: '/xiaomi/historial',
        ),
        (
          label: 'Xiaomi · Estadísticas',
          icon: Icons.bar_chart_rounded,
          route: '/xiaomi/estadisticas',
        ),

        // Servers + others
        (
          label: 'Servidores · Previ',
          icon: Icons.preview_rounded,
          route: '/servers/previ',
        ),
        (
          label: 'Servidores · Servidores',
          icon: Icons.storage_rounded,
          route: '/servers/servidores',
        ),
        (
          label: 'Sentinel AI · Mesa Activa',
          icon: Icons.table_restaurant_rounded,
          route: '/sentinel/tables',
        ),
        (
          label: 'Sentinel AI · Imágenes Activas',
          icon: Icons.downloading_rounded,
          route: '/sentinel/active',
        ),
        (
          label: 'Análisis y Servicios · Dashboard',
          icon: Icons.analytics_rounded,
          route: '/analisis/dashboard',
        ),
        (
          label: 'Análisis y Servicios · Gestión',
          icon: Icons.settings_suggest_rounded,
          route: '/analisis/management',
        ),
      ];

      final filtered = entries
          .where((e) => e.label.toLowerCase().contains(q))
          .toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SidebarSectionHeader(title: 'RESULTADOS'),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 6),
              child: Text(
                'No matches',
                style: TextStyle(
                  color: textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          for (final e in filtered)
            _SidebarTile(
              label: e.label,
              icon: e.icon,
              selected: routeName == e.route,
              onTap: () =>
                  _navigate(context, e.route, closeOverlay: !widget.permanent),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
        ],
      );
    }

    bool isRoute(String r) => routeName == r;
    bool routeIn(Iterable<String> routes) =>
        routeName != null && routes.contains(routeName);

    const amazonRoutes = [
      '/amazon/grading',
      '/amazon/sorting',
      '/amazon/quality',
      '/amazon/inventory',
      '/amazon/inventory/picking',
      '/amazon/inventory/receiving',
      '/amazon/inventory/icqa',
      '/amazon/herramientas/closebox',
      '/amazon/herramientas/findbox',
      '/amazon/herramientas/finddsn',
    ];
    const inventoryRoutes = [
      '/amazon/inventory',
      '/amazon/inventory/picking',
      '/amazon/inventory/receiving',
      '/amazon/inventory/icqa',
    ];
    const amazonToolsRoutes = [
      '/amazon/herramientas/closebox',
      '/amazon/herramientas/findbox',
      '/amazon/herramientas/finddsn',
    ];
    const serialRoutes = [
      '/serials/cambio',
      '/serials/change',
      '/serials/labels',
      '/serials/masks',
      '/serials/serial-changes',
    ];
    const serverRoutes = ['/servers/previ', '/servers/servidores'];
    const igualdadRoutes = [
      '/igualdad/dashboard',
      '/igualdad/entrada',
      '/igualdad/registro/smartphone',
      '/igualdad/registro/pulsera',
      '/igualdad/registro/powerbank',
      '/igualdad/registro/boton',
      '/igualdad/historial',
    ];
    const igualdadRegRoutes = [
      '/igualdad/registro/smartphone',
      '/igualdad/registro/pulsera',
      '/igualdad/registro/powerbank',
      '/igualdad/registro/boton',
    ];
    const xiaomiRoutes = [
      '/xiaomi/historial',
      '/xiaomi/registro/unidades',
      '/xiaomi/cerrar_cesb',
      '/xiaomi/estadisticas',
    ];
    const orderOpsRoutes = [
      '/orderops/queue',
      '/orderops/work-items',
      '/orderops/activity',
      '/orderops/memory',
    ];

    final amazonExpanded = routeIn(amazonRoutes);
    final inventoryExpanded = routeIn(inventoryRoutes);
    final amazonToolsExpanded = routeIn(amazonToolsRoutes);
    final igualdadExpanded = routeIn(igualdadRoutes);
    final igualdadRegExpanded = routeIn(igualdadRegRoutes);
    final serialsExpanded = routeIn(serialRoutes);
    final serversExpanded = routeIn(serverRoutes);
    final xiaomiExpanded = routeIn(xiaomiRoutes);
    final orderOpsExpanded = routeIn(orderOpsRoutes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SidebarSectionHeader(title: 'PROYECTOS'),
        SidebarExpansionTile(
          title: 'Amazon',
          icon: Icons.shopping_basket_rounded,
          highlight: highlight,
          textPrimary: textPrimary,
          initiallyExpanded: amazonExpanded,
          children: [
            _SidebarTile(
              label: 'Grading',
              icon: Icons.grade_rounded,
              selected: isRoute('/amazon/grading'),
              onTap: () => _navigate(
                context,
                '/amazon/grading',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Sorting',
              icon: Icons.sort_rounded,
              selected: isRoute('/amazon/sorting'),
              onTap: () => _navigate(
                context,
                '/amazon/sorting',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Quality Check',
              icon: Icons.search_off_rounded,
              selected: isRoute('/amazon/quality'),
              onTap: () => _navigate(
                context,
                '/amazon/quality',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            SidebarExpansionTile(
              title: 'Inventory',
              icon: Icons.inventory_2_rounded,
              highlight: highlight,
              textPrimary: textPrimary,
              initiallyExpanded: inventoryExpanded,
              nested: true,
              children: [
                _SidebarTile(
                  label: 'Registro',
                  icon: Icons.app_registration_rounded,
                  selected: isRoute('/amazon/inventory'),
                  onTap: () => _navigate(
                    context,
                    '/amazon/inventory',
                    closeOverlay: !permanent,
                  ),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
                _SidebarTile(
                  label: 'Picking',
                  icon: Icons.shopping_cart_rounded,
                  selected: isRoute('/amazon/inventory/picking'),
                  onTap: () => _navigate(
                    context,
                    '/amazon/inventory/picking',
                    closeOverlay: !permanent,
                  ),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
                _SidebarTile(
                  label: 'Receiving',
                  icon: Icons.move_to_inbox_rounded,
                  selected: isRoute('/amazon/inventory/receiving'),
                  onTap: () => _navigate(
                    context,
                    '/amazon/inventory/receiving',
                    closeOverlay: !permanent,
                  ),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
                _SidebarTile(
                  label: 'ICQA',
                  icon: Icons.check_circle_rounded,
                  selected: isRoute('/amazon/inventory/icqa'),
                  onTap: () => _navigate(
                    context,
                    '/amazon/inventory/icqa',
                    closeOverlay: !permanent,
                  ),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
              ],
            ),
            SidebarExpansionTile(
              title: 'Herramientas',
              icon: Icons.build_rounded,
              highlight: highlight,
              textPrimary: textPrimary,
              initiallyExpanded: amazonToolsExpanded,
              nested: true,
              children: [
                _SidebarTile(
                  label: 'Cerrar Box',
                  icon: Icons.close_rounded,
                  selected: isRoute('/amazon/herramientas/closebox'),
                  onTap: () => _navigate(
                    context,
                    '/amazon/herramientas/closebox',
                    closeOverlay: !permanent,
                  ),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
                _SidebarTile(
                  label: 'Buscar Box',
                  icon: Icons.find_in_page_rounded,
                  selected: isRoute('/amazon/herramientas/findbox'),
                  onTap: () => _navigate(
                    context,
                    '/amazon/herramientas/findbox',
                    closeOverlay: !permanent,
                  ),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
                _SidebarTile(
                  label: 'Buscar DSN',
                  icon: Icons.search_rounded,
                  selected: isRoute('/amazon/herramientas/finddsn'),
                  onTap: () => _navigate(
                    context,
                    '/amazon/herramientas/finddsn',
                    closeOverlay: !permanent,
                  ),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
              ],
            ),
          ],
        ),
        if ([
          'chief',
          'admin',
          'clerc',
          'technitian',
        ].any((r) => (user?.role ?? '').toLowerCase().contains(r))) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(
              thickness: 0.6,
              height: 1,
              color: textMuted.withOpacity(0.12),
            ),
          ),
          SidebarExpansionTile(
            title: 'OrderOps AI',
            icon: Icons.psychology_rounded,
            highlight: highlight,
            textPrimary: textPrimary,
            initiallyExpanded: orderOpsExpanded,
            children: [
              _SidebarTile(
                label: 'Console / Queue',
                icon: Icons.list_alt_rounded,
                selected: isRoute('/orderops/queue'),
                onTap: () => _navigate(
                  context,
                  '/orderops/queue',
                  closeOverlay: !permanent,
                ),
                highlight: highlight,
                textPrimary: textPrimary,
                isDark: isDark,
              ),
              _SidebarTile(
                label: 'Work Items',
                icon: Icons.task_alt_rounded,
                selected: isRoute('/orderops/work-items'),
                onTap: () => _navigate(
                  context,
                  '/orderops/work-items',
                  closeOverlay: !permanent,
                ),
                highlight: highlight,
                textPrimary: textPrimary,
                isDark: isDark,
              ),
              _SidebarTile(
                label: 'Activity Log',
                icon: Icons.history_edu_rounded,
                selected: isRoute('/orderops/activity'),
                onTap: () => _navigate(
                  context,
                  '/orderops/activity',
                  closeOverlay: !permanent,
                ),
                highlight: highlight,
                textPrimary: textPrimary,
                isDark: isDark,
              ),
              _SidebarTile(
                label: 'Agent Q/A',
                icon: Icons.question_answer_rounded,
                selected: isRoute('/orderops/memory'),
                onTap: () => _navigate(
                  context,
                  '/orderops/memory',
                  closeOverlay: !permanent,
                ),
                highlight: highlight,
                textPrimary: textPrimary,
                isDark: isDark,
              ),
            ],
          ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Divider(
            thickness: 0.6,
            height: 1,
            color: textMuted.withOpacity(0.12),
          ),
        ),
        SidebarExpansionTile(
          title: 'M. Igualdad',
          icon: Icons.group_rounded,
          highlight: highlight,
          textPrimary: textPrimary,
          initiallyExpanded: igualdadExpanded,
          children: [
            _SidebarTile(
              label: 'Dashboard',
              icon: Icons.dashboard_rounded,
              selected: isRoute('/igualdad/dashboard'),
              onTap: () => _navigate(
                context,
                '/igualdad/dashboard',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Entrada Stock',
              icon: Icons.login_rounded,
              selected: isRoute('/igualdad/entrada'),
              onTap: () => _navigate(
                context,
                '/igualdad/entrada',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            SidebarExpansionTile(
              title: 'Registros',
              icon: Icons.folder_open_rounded,
              highlight: highlight,
              textPrimary: textPrimary,
              initiallyExpanded: igualdadRegExpanded,
              nested: true,
              children: [
                _SidebarTile(
                  label: 'Smartphone',
                  icon: Icons.smartphone_rounded,
                  selected: isRoute('/igualdad/registro/smartphone'),
                  onTap: () => _navigate(
                    context,
                    '/igualdad/registro/smartphone',
                    closeOverlay: !permanent,
                  ),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
                _SidebarTile(
                  label: 'Pulsera',
                  icon: Icons.watch_rounded,
                  selected: isRoute('/igualdad/registro/pulsera'),
                  onTap: () => _navigate(
                    context,
                    '/igualdad/registro/pulsera',
                    closeOverlay: !permanent,
                  ),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
                _SidebarTile(
                  label: 'Powerbank',
                  icon: Icons.battery_charging_full_rounded,
                  selected: isRoute('/igualdad/registro/powerbank'),
                  onTap: () => _navigate(
                    context,
                    '/igualdad/registro/powerbank',
                    closeOverlay: !permanent,
                  ),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
                _SidebarTile(
                  label: 'Botón',
                  icon: Icons.radio_button_checked_rounded,
                  selected: isRoute('/igualdad/registro/boton'),
                  onTap: () => _navigate(
                    context,
                    '/igualdad/registro/boton',
                    closeOverlay: !permanent,
                  ),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
              ],
            ),
            _SidebarTile(
              label: 'Historial',
              icon: Icons.history_rounded,
              selected: isRoute('/igualdad/historial'),
              onTap: () => _navigate(
                context,
                '/igualdad/historial',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
          ],
        ),
        SidebarExpansionTile(
          title: 'Serials',
          icon: Icons.qr_code_rounded,
          highlight: highlight,
          textPrimary: textPrimary,
          initiallyExpanded: serialsExpanded,
          children: [
            _SidebarTile(
              label: 'Registro Serial',
              icon: Icons.change_circle_rounded,
              selected: isRoute('/serials/cambio'),
              onTap: () => _navigate(
                context,
                '/serials/cambio',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Cambio Serial',
              icon: Icons.swap_horiz_rounded,
              selected: isRoute('/serials/change'),
              onTap: () => _navigate(
                context,
                '/serials/change',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Etiquetas',
              icon: Icons.label_rounded,
              selected: isRoute('/serials/labels'),
              onTap: () => _navigate(
                context,
                '/serials/labels',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Máscaras',
              icon: Icons.masks_rounded,
              selected: isRoute('/serials/masks'),
              onTap: () => _navigate(
                context,
                '/serials/masks',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),

            _SidebarTile(
              label: 'Historial Cambios',
              icon: Icons.history_edu_rounded,
              selected: isRoute('/serials/serial-changes'),
              onTap: () => _navigate(
                context,
                '/serials/serial-changes',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
          ],
        ),
        SidebarExpansionTile(
          title: 'Xiaomi',
          icon: Icons.phone_android_rounded,
          highlight: highlight,
          textPrimary: textPrimary,
          initiallyExpanded: xiaomiExpanded,
          children: [
            _SidebarTile(
              label: 'Registro Unidades',
              icon: Icons.app_registration_rounded,
              selected: isRoute('/xiaomi/registro/unidades'),
              onTap: () => _navigate(
                context,
                '/xiaomi/registro/unidades',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Cerrar CESB',
              icon: Icons.check_circle_outline_rounded,
              selected: isRoute('/xiaomi/cerrar_cesb'),
              onTap: () => _navigate(
                context,
                '/xiaomi/cerrar_cesb',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Historial',
              icon: Icons.history_rounded,
              selected: isRoute('/xiaomi/historial'),
              onTap: () => _navigate(
                context,
                '/xiaomi/historial',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Estadísticas',
              icon: Icons.bar_chart_rounded,
              selected: isRoute('/xiaomi/estadisticas'),
              onTap: () => _navigate(
                context,
                '/xiaomi/estadisticas',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
          ],
        ),
        SidebarExpansionTile(
          title: 'Servidores',
          icon: Icons.dns_rounded,
          highlight: highlight,
          textPrimary: textPrimary,
          initiallyExpanded: serversExpanded,
          children: [
            _SidebarTile(
              label: 'Previ',
              icon: Icons.preview_rounded,
              selected: isRoute('/servers/previ'),
              onTap: () => _navigate(
                context,
                '/servers/previ',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Servidores',
              icon: Icons.storage_rounded,
              selected: isRoute('/servers/servidores'),
              onTap: () => _navigate(
                context,
                '/servers/servidores',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
          ],
        ),
        SidebarExpansionTile(
          title: 'Sentinel AI',
          icon: Icons.security_rounded,
          highlight: highlight,
          textPrimary: textPrimary,
          initiallyExpanded: [
            '/sentinel/active',
            '/sentinel/tables',
          ].contains(routeName),
          children: [
            _SidebarTile(
              label: 'Mesa Activa',
              icon: Icons.table_restaurant_rounded,
              selected: isRoute('/sentinel/tables'),
              onTap: () => _navigate(
                context,
                '/sentinel/tables',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Imágenes Activas',
              icon: Icons.downloading_rounded,
              selected: isRoute('/sentinel/active'),
              onTap: () => _navigate(
                context,
                '/sentinel/active',
                closeOverlay: !permanent,
              ),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
          ],
        ),
        if (user != null && (user.role == 'admin' || user.role == 'chief')) ...[
          SidebarExpansionTile(
            title: 'Análisis y Servicios',
            icon: Icons.analytics_rounded,
            highlight: highlight,
            textPrimary: textPrimary,
            initiallyExpanded: routeIn([
              '/analisis/dashboard',
              '/analisis/management',
            ]),
            children: [
              _SidebarTile(
                label: 'Dashboard',
                icon: Icons.dashboard_rounded,
                selected: isRoute('/analisis/dashboard'),
                onTap: () => _navigate(
                  context,
                  '/analisis/dashboard',
                  closeOverlay: !permanent,
                ),
                highlight: highlight,
                textPrimary: textPrimary,
                isDark: isDark,
              ),
              _SidebarTile(
                label: 'Gestión',
                icon: Icons.settings_suggest_rounded,
                selected: isRoute('/analisis/management'),
                onTap: () => _navigate(
                  context,
                  '/analisis/management',
                  closeOverlay: !permanent,
                ),
                highlight: highlight,
                textPrimary: textPrimary,
                isDark: isDark,
              ),
            ],
          ),
        ] else ...[
          _SidebarTile(
            label: 'Análisis y Servicios',
            icon: Icons.analytics_rounded,
            selected: isRoute('/analisis/dashboard'),
            onTap: () => _navigate(
              context,
              '/analisis/dashboard',
              closeOverlay: !permanent,
            ),
            highlight: highlight,
            textPrimary: textPrimary,
            isDark: isDark,
          ),
        ],
      ],
    );
  }
}

class _SidebarTile extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color highlight;
  final Color textPrimary;
  final bool isDark;
  final bool nested;
  final Widget? trailing;

  const _SidebarTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.highlight,
    required this.textPrimary,
    required this.isDark,
    this.nested = false,
    this.trailing,
  });

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.02,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.highlight;
    final isDark = widget.isDark;

    final bgSelected = active.withOpacity(isDark ? 0.18 : 0.12);
    final bgHover = isDark
        ? Colors.white.withOpacity(0.06)
        : Colors.black.withOpacity(0.04);

    final borderSelected = active.withOpacity(isDark ? 0.30 : 0.22);
    final borderIdle = Colors.transparent;

    final iconColor = widget.selected
        ? active
        : (_isHovered
              ? widget.textPrimary.withOpacity(0.90)
              : widget.textPrimary.withOpacity(0.62));

    final textColor = widget.selected
        ? widget.textPrimary.withOpacity(0.88)
        : (_isHovered
              ? widget.textPrimary.withOpacity(0.92)
              : widget.textPrimary.withOpacity(0.72));

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _controller.reverse();
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            margin: EdgeInsets.symmetric(
              vertical: 3,
              horizontal: widget.nested ? 2 : 6,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: widget.nested ? 14 : 14,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: widget.selected
                  ? bgSelected
                  : (_isHovered ? bgHover : Colors.transparent),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.selected ? borderSelected : borderIdle,
                width: 0.9,
              ),
              boxShadow: widget.selected
                  ? [
                      BoxShadow(
                        color: active.withOpacity(isDark ? 0.18 : 0.12),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 20, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: widget.selected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      fontSize: 13.5,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
                if (widget.selected && widget.trailing == null)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppleSidebarSurface extends StatelessWidget {
  final Widget child;
  const AppleSidebarSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color bg = isDark
        ? const Color(0xFF0B1116).withOpacity(0.62)
        : const Color(0xFFF6F7FA).withOpacity(0.78);

    final Color border = isDark
        ? Colors.white.withOpacity(0.10)
        : Colors.black.withOpacity(0.06);

    final Color shadow = Colors.black.withOpacity(isDark ? 0.32 : 0.10);

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: border, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: shadow,
                blurRadius: 28,
                offset: const Offset(10, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class SidebarSectionHeader extends StatelessWidget {
  final String title;
  const SidebarSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color c = isDark
        ? Colors.white.withOpacity(0.55)
        : Colors.black.withOpacity(0.45);

    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 6, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class AppleSidebarSearch extends StatefulWidget {
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  const AppleSidebarSearch({
    super.key,
    required this.hint,
    this.onSubmitted,
    this.onChanged,
  });

  @override
  State<AppleSidebarSearch> createState() => _AppleSidebarSearchState();
}

class _AppleSidebarSearchState extends State<AppleSidebarSearch> {
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _controller = TextEditingController();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(
      () => setState(() => _isFocused = _focusNode.hasFocus),
    );
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final fill = isDark
        ? Colors.white.withOpacity(0.06)
        : Colors.black.withOpacity(0.04);
    final borderIdle = isDark
        ? Colors.white.withOpacity(0.10)
        : Colors.black.withOpacity(0.06);
    final borderFocused = theme.colorScheme.primary.withOpacity(0.5);

    final text = isDark
        ? Colors.white.withOpacity(0.85)
        : Colors.black.withOpacity(0.80);
    final hintC = isDark
        ? Colors.white.withOpacity(0.45)
        : Colors.black.withOpacity(0.40);

    final hasText = _controller.text.trim().isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 40,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isFocused ? borderFocused : borderIdle,
          width: _isFocused ? 1.5 : 0.8,
        ),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.2),
                  blurRadius: 8,
                  spreadRadius: -1,
                ),
              ]
            : [],
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: TextStyle(
          color: text,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: hintC),
          suffixIcon: hasText
              ? IconButton(
                  tooltip: 'Clear',
                  icon: Icon(Icons.close_rounded, size: 18, color: hintC),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged?.call('');
                  },
                )
              : null,
          hintText: widget.hint,
          hintStyle: TextStyle(
            color: hintC,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 12,
          ),
        ),
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}

Future<void> showAppSidebar(
  BuildContext context, {
  User? user,
  String? currentRoute,
}) {
  if (_AppNavState._isOpen) return Future.value();
  _AppNavState._isOpen = true;
  final currentRouteName =
      currentRoute ?? ModalRoute.of(context)?.settings.name;
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Navigation',
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (ctx, a1, a2) {
      final effectiveUser =
          user ?? (Provider.of<ApiService>(ctx, listen: false).currentUser);
      return Align(
        alignment: Alignment.centerLeft,
        child: MainSidebar(
          user: effectiveUser,
          permanent: false,
          currentRoute: currentRouteName,
        ),
      );
    },
    transitionBuilder: (ctx, a1, a2, child) {
      return Stack(
        children: [
          // scrim
          FadeTransition(
            opacity: CurvedAnimation(parent: a1, curve: Curves.easeOut),
            child: GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: Container(color: Colors.black.withOpacity(0.18)),
            ),
          ),
          // blur
          FadeTransition(
            opacity: CurvedAnimation(parent: a1, curve: Curves.easeOut),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: const SizedBox.expand(),
            ),
          ),
          // sidebar
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: a1, curve: Curves.easeOutCubic)),
            child: ScaleTransition(
              scale: Tween(begin: 0.98, end: 1.0).animate(
                CurvedAnimation(parent: a1, curve: Curves.easeOutCubic),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: child,
              ),
            ),
          ),
        ],
      );
    },
  ).then((_) {
    _AppNavState._isOpen = false;
  });
}

class _AppNavState {
  static bool _isOpen = false;
}

class SidebarExpansionTile extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color highlight;
  final Color textPrimary;
  final bool initiallyExpanded;
  final List<Widget> children;
  final bool nested;

  const SidebarExpansionTile({
    super.key,
    required this.title,
    required this.icon,
    required this.highlight,
    required this.textPrimary,
    required this.initiallyExpanded,
    required this.children,
    this.nested = false,
  });

  @override
  State<SidebarExpansionTile> createState() => _SidebarExpansionTileState();
}

class _SidebarExpansionTileState extends State<SidebarExpansionTile> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant SidebarExpansionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If route changes and wants it open, follow it.
    if (widget.initiallyExpanded && !_expanded) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final expanded = _expanded;

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
      ),
      child: ExpansionTile(
        key: PageStorageKey('exp_${widget.title}_${widget.nested}'),
        initiallyExpanded: expanded,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        dense: true,
        visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
        minTileHeight: 42,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        tilePadding: EdgeInsets.symmetric(horizontal: widget.nested ? 10 : 8),
        childrenPadding: EdgeInsets.only(left: widget.nested ? 12 : 0),
        leading: Icon(
          widget.icon,
          color: expanded
              ? widget.highlight
              : widget.textPrimary.withOpacity(0.7),
          size: 20,
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            color: expanded ? widget.highlight : widget.textPrimary,
            fontWeight: expanded ? FontWeight.w700 : FontWeight.w600,
            fontSize: 14,
          ),
        ),
        trailing: AnimatedRotation(
          turns: expanded ? 0.5 : 0.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: expanded
                ? widget.highlight
                : widget.textPrimary.withOpacity(0.5),
            size: 20,
          ),
        ),
        children: widget.children,
      ),
    );
  }
}

class EdgeNavHandle extends StatefulWidget {
  final User? user;
  final double width;
  final String? currentRoute;
  final bool showIndicator;

  const EdgeNavHandle({
    super.key,
    this.user,
    this.width = 28,
    this.currentRoute,
    this.showIndicator = false,
  });

  @override
  State<EdgeNavHandle> createState() => _EdgeNavHandleState();
}

class _EdgeNavHandleState extends State<EdgeNavHandle> {
  bool _hovering = false;
  Future<void>? _pending;

  void _scheduleOpen(BuildContext context, String? route) {
    if (_pending != null) return;
    _pending = Future.delayed(const Duration(milliseconds: 180)).then((_) {
      _pending = null;
      if (!mounted || !_hovering) return;
      showAppSidebar(context, user: widget.user, currentRoute: route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Auto-resolve route if not provided, to fix overlay context issues
    final actualRoute =
        widget.currentRoute ?? ModalRoute.of(context)?.settings.name;

    return MouseRegion(
      onEnter: (_) {
        _hovering = true;
        _scheduleOpen(context, actualRoute);
      },
      onExit: (_) {
        _hovering = false;
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showAppSidebar(
          context,
          user: widget.user,
          currentRoute: actualRoute,
        ),
        child: SizedBox(
          width: widget.width,
          child: widget.showIndicator
              ? Center(
                  child: Container(
                    width: 24,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black.withOpacity(0.1),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.2)
                            : Colors.black.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: isDark
                          ? Colors.white.withOpacity(0.7)
                          : Colors.black.withOpacity(0.6),
                      size: 20,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
