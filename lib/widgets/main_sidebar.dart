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
class MainSidebar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    ThemeController? theme;
    try {
      theme = Provider.of<ThemeController>(context);
    } catch (_) {
      theme = null;
    }
    final isDark = theme?.isDark ?? true;
    final routeName = currentRoute ?? ModalRoute.of(context)?.settings.name;
    final logoAsset = isDark
        ? 'assets/favicon-brightmode.png'
        : 'assets/favicon-darkmode.png';
    final sidebarColor = isDark
        ? const Color(0xFF0B1116).withOpacity(0.75) // More opaque frost
        : const Color(0xFFF0F3F7).withOpacity(0.75);
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textMuted = isDark ? Colors.white70 : Colors.black54;
    final highlight = Theme.of(context).colorScheme.primary;

    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320, minWidth: 220),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 260,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: sidebarColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(isDark ? 0.05 : 0.2),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 24,
                  offset: const Offset(4, 0),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLogo(context, logoAsset, textPrimary),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSection(
                          context,
                          'PROYECTOS',
                          textPrimary,
                          textMuted,
                          routeName: routeName,
                          highlight: highlight,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 24),
                        if ((user?.role ?? '').toLowerCase().contains(
                          'admin',
                        )) ...[
                          _buildExpansionTile(
                            context,
                            title: 'Recursos Humanos',
                            icon: Icons.people_alt_rounded,
                            highlight: highlight,
                            textPrimary: textPrimary,
                            isExpanded: false,
                            children: [
                              _SidebarTile(
                                label: 'Fichaje',
                                icon: Icons.access_time_rounded,
                                selected: false,
                                onTap: () => _navigate(context, '/hr/fichaje'),
                                highlight: highlight,
                                textPrimary: textPrimary,
                                isDark: isDark,
                              ),
                              _SidebarTile(
                                label: 'Alta Empleado',
                                icon: Icons.person_add_rounded,
                                selected: false,
                                onTap: () =>
                                    _navigate(context, '/hr/alta_empleado'),
                                highlight: highlight,
                                textPrimary: textPrimary,
                                isDark: isDark,
                              ),
                              _SidebarTile(
                                label: 'Registro Fichajes',
                                icon: Icons.format_list_bulleted_rounded,
                                selected: false,
                                onTap: () =>
                                    _navigate(context, '/hr/registro_fichaje'),
                                highlight: highlight,
                                textPrimary: textPrimary,
                                isDark: isDark,
                              ),
                              _SidebarTile(
                                label: 'Asignación Trabajo',
                                icon: Icons.work_outline_rounded,
                                selected: false,
                                onTap: () => _navigate(
                                  context,
                                  '/hr/asignacion_trabajo',
                                ),
                                highlight: highlight,
                                textPrimary: textPrimary,
                                isDark: isDark,
                              ),
                              _SidebarTile(
                                label: 'Gestión Empleado',
                                icon: Icons.manage_accounts_rounded,
                                selected: false,
                                onTap: () =>
                                    _navigate(context, '/hr/gestion_empleado'),
                                highlight: highlight,
                                textPrimary: textPrimary,
                                isDark: isDark,
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Divider(color: textMuted.withOpacity(0.2), height: 32),
                _buildFooter(
                  context,
                  isDark,
                  textPrimary,
                  textMuted,
                  logoAsset,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return permanent
        ? content
        : Material(type: MaterialType.transparency, child: content);
  }

  Widget _buildLogo(BuildContext context, String logoAsset, Color textPrimary) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).pop();
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
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
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
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: -0.5,
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

  void _navigate(BuildContext context, String route) {
    Navigator.of(context).pop();
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => Navigator.of(context, rootNavigator: true).pushNamed(route),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    Color textPrimary,
    Color textMuted, {
    required String? routeName,
    required Color highlight,
    required bool isDark,
  }) {
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
    ];

    final amazonExpanded = routeIn(amazonRoutes);
    final inventoryExpanded = routeIn(inventoryRoutes);
    final amazonToolsExpanded = routeIn(amazonToolsRoutes);
    final igualdadExpanded = routeIn(igualdadRoutes);
    final igualdadRegExpanded = routeIn(igualdadRegRoutes);
    final serialsExpanded = routeIn(serialRoutes);
    final serversExpanded = routeIn(serverRoutes);
    final xiaomiExpanded = routeIn(xiaomiRoutes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              color: textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        _buildExpansionTile(
          context,
          title: 'Amazon',
          icon: Icons.shopping_basket_rounded,
          highlight: highlight,
          textPrimary: textPrimary,
          isExpanded: amazonExpanded,
          children: [
            _SidebarTile(
              label: 'Grading',
              icon: Icons.grade_rounded,
              selected: isRoute('/amazon/grading'),
              onTap: () => _navigate(context, '/amazon/grading'),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Sorting',
              icon: Icons.sort_rounded,
              selected: isRoute('/amazon/sorting'),
              onTap: () => _navigate(context, '/amazon/sorting'),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Quality Check',
              icon: Icons.search_off_rounded,
              selected: isRoute('/amazon/quality'),
              onTap: () => _navigate(context, '/amazon/quality'),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _buildExpansionTile(
              context,
              title: 'Inventory',
              icon: Icons.inventory_2_rounded,
              highlight: highlight,
              textPrimary: textPrimary,
              isExpanded: inventoryExpanded,
              nested: true,
              children: [
                _SidebarTile(
                  label: 'Registro',
                  icon: Icons.app_registration_rounded,
                  selected: isRoute('/amazon/inventory'),
                  onTap: () => _navigate(context, '/amazon/inventory'),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
                _SidebarTile(
                  label: 'Picking',
                  icon: Icons.shopping_cart_rounded,
                  selected: isRoute('/amazon/inventory/picking'),
                  onTap: () => _navigate(context, '/amazon/inventory/picking'),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
                _SidebarTile(
                  label: 'Receiving',
                  icon: Icons.move_to_inbox_rounded,
                  selected: isRoute('/amazon/inventory/receiving'),
                  onTap: () =>
                      _navigate(context, '/amazon/inventory/receiving'),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
                _SidebarTile(
                  label: 'ICQA',
                  icon: Icons.check_circle_rounded,
                  selected: isRoute('/amazon/inventory/icqa'),
                  onTap: () => _navigate(context, '/amazon/inventory/icqa'),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
              ],
            ),
            _buildExpansionTile(
              context,
              title: 'Herramientas',
              icon: Icons.build_rounded,
              highlight: highlight,
              textPrimary: textPrimary,
              isExpanded: amazonToolsExpanded,
              nested: true,
              children: [
                _SidebarTile(
                  label: 'Cerrar Box',
                  icon: Icons.close_rounded,
                  selected: isRoute('/amazon/herramientas/closebox'),
                  onTap: () =>
                      _navigate(context, '/amazon/herramientas/closebox'),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
                _SidebarTile(
                  label: 'Buscar Box',
                  icon: Icons.find_in_page_rounded,
                  selected: isRoute('/amazon/herramientas/findbox'),
                  onTap: () =>
                      _navigate(context, '/amazon/herramientas/findbox'),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
                _SidebarTile(
                  label: 'Buscar DSN',
                  icon: Icons.search_rounded,
                  selected: isRoute('/amazon/herramientas/finddsn'),
                  onTap: () =>
                      _navigate(context, '/amazon/herramientas/finddsn'),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
              ],
            ),
          ],
        ),
        _buildExpansionTile(
          context,
          title: 'M. Igualdad',
          icon: Icons.group_rounded,
          highlight: highlight,
          textPrimary: textPrimary,
          isExpanded: igualdadExpanded,
          children: [
            _SidebarTile(
              label: 'Dashboard',
              icon: Icons.dashboard_rounded,
              selected: isRoute('/igualdad/dashboard'),
              onTap: () => _navigate(context, '/igualdad/dashboard'),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Entrada Stock',
              icon: Icons.login_rounded,
              selected: isRoute('/igualdad/entrada'),
              onTap: () => _navigate(context, '/igualdad/entrada'),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _buildExpansionTile(
              context,
              title: 'Registros',
              icon: Icons.folder_open_rounded,
              highlight: highlight,
              textPrimary: textPrimary,
              isExpanded: igualdadRegExpanded,
              nested: true,
              children: [
                _SidebarTile(
                  label: 'Smartphone',
                  icon: Icons.smartphone_rounded,
                  selected: isRoute('/igualdad/registro/smartphone'),
                  onTap: () =>
                      _navigate(context, '/igualdad/registro/smartphone'),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
                _SidebarTile(
                  label: 'Pulsera',
                  icon: Icons.watch_rounded,
                  selected: isRoute('/igualdad/registro/pulsera'),
                  onTap: () => _navigate(context, '/igualdad/registro/pulsera'),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
                _SidebarTile(
                  label: 'Powerbank',
                  icon: Icons.battery_charging_full_rounded,
                  selected: isRoute('/igualdad/registro/powerbank'),
                  onTap: () =>
                      _navigate(context, '/igualdad/registro/powerbank'),
                  highlight: highlight,
                  textPrimary: textPrimary,
                  isDark: isDark,
                  nested: true,
                ),
                _SidebarTile(
                  label: 'Botón',
                  icon: Icons.radio_button_checked_rounded,
                  selected: isRoute('/igualdad/registro/boton'),
                  onTap: () => _navigate(context, '/igualdad/registro/boton'),
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
              onTap: () => _navigate(context, '/igualdad/historial'),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
          ],
        ),
        _buildExpansionTile(
          context,
          title: 'Serials',
          icon: Icons.qr_code_rounded,
          highlight: highlight,
          textPrimary: textPrimary,
          isExpanded: serialsExpanded,
          children: [
            _SidebarTile(
              label: 'Registro Serial',
              icon: Icons.change_circle_rounded,
              selected: isRoute('/serials/cambio'),
              onTap: () => _navigate(context, '/serials/cambio'),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Cambio Serial',
              icon: Icons.swap_horiz_rounded,
              selected: isRoute('/serials/change'),
              onTap: () => _navigate(context, '/serials/change'),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Etiquetas',
              icon: Icons.label_rounded,
              selected: isRoute('/serials/labels'),
              onTap: () => _navigate(context, '/serials/labels'),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Máscaras',
              icon: Icons.masks_rounded,
              selected: isRoute('/serials/masks'),
              onTap: () => _navigate(context, '/serials/masks'),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),

            _SidebarTile(
              label: 'Historial Cambios',
              icon: Icons.history_edu_rounded,
              selected: isRoute('/serials/serial-changes'),
              onTap: () => _navigate(context, '/serials/serial-changes'),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
          ],
        ),
        _buildExpansionTile(
          context,
          title: 'Xiaomi',
          icon: Icons.phone_android_rounded,
          highlight: highlight,
          textPrimary: textPrimary,
          isExpanded: xiaomiExpanded,
          children: [
            _SidebarTile(
              label: 'Registro Unidades',
              icon: Icons.app_registration_rounded,
              selected: isRoute('/xiaomi/registro/unidades'),
              onTap: () => _navigate(context, '/xiaomi/registro/unidades'),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Cerrar CESB',
              icon: Icons.check_circle_outline_rounded,
              selected: isRoute('/xiaomi/cerrar_cesb'),
              onTap: () => _navigate(context, '/xiaomi/cerrar_cesb'),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Historial',
              icon: Icons.history_rounded,
              selected: isRoute('/xiaomi/historial'),
              onTap: () => _navigate(context, '/xiaomi/historial'),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
          ],
        ),
        _buildExpansionTile(
          context,
          title: 'Servidores',
          icon: Icons.dns_rounded,
          highlight: highlight,
          textPrimary: textPrimary,
          isExpanded: serversExpanded,
          children: [
            _SidebarTile(
              label: 'Previ',
              icon: Icons.preview_rounded,
              selected: isRoute('/servers/previ'),
              onTap: () => _navigate(context, '/servers/previ'),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
            _SidebarTile(
              label: 'Servidores',
              icon: Icons.storage_rounded,
              selected: isRoute('/servers/servidores'),
              onTap: () => _navigate(context, '/servers/servidores'),
              highlight: highlight,
              textPrimary: textPrimary,
              isDark: isDark,
            ),
          ],
        ),
        _SidebarTile(
          label: 'Sentinel AI',
          icon: Icons.security_rounded,
          selected: isRoute('/sentinel'),
          onTap: () => _navigate(context, '/sentinel'),
          highlight: highlight,
          textPrimary: textPrimary,
          isDark: isDark,
        ),
        _SidebarTile(
          label: 'Análisis y Servicios',
          icon: Icons.analytics_rounded,
          selected: isRoute('/analisis/dashboard'),
          onTap: () => _navigate(context, '/analisis/dashboard'),
          highlight: highlight,
          textPrimary: textPrimary,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildExpansionTile(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color highlight,
    required Color textPrimary,
    required bool isExpanded,
    required List<Widget> children,
    bool nested = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: isExpanded,
        tilePadding: EdgeInsets.symmetric(horizontal: nested ? 16 : 12),
        childrenPadding: EdgeInsets.only(left: nested ? 12 : 0),
        leading: Icon(
          icon,
          color: isExpanded ? highlight : textPrimary.withOpacity(0.7),
          size: 20,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isExpanded ? highlight : textPrimary,
            fontWeight: isExpanded ? FontWeight.w700 : FontWeight.w600,
            fontSize: 14,
          ),
        ),
        iconColor: highlight,
        collapsedIconColor: textPrimary.withOpacity(0.7),
        trailing: RotationTransition(
          turns: AlwaysStoppedAnimation(isExpanded ? 0.5 : 0),
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: isExpanded ? highlight : textPrimary.withOpacity(0.5),
            size: 20,
          ),
        ),
        children: children,
      ),
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
    final activeColor = widget.highlight;
    final inactiveColor = widget.textPrimary.withOpacity(0.7);

    // Gradient for selected state
    final selectedGradient = LinearGradient(
      colors: [
        activeColor.withOpacity(widget.isDark ? 0.2 : 0.15),
        activeColor.withOpacity(widget.isDark ? 0.05 : 0.02),
      ],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );

    final hoverColor = widget.isDark
        ? Colors.white.withOpacity(0.05)
        : Colors.black.withOpacity(0.05);

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
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            margin: EdgeInsets.symmetric(
              vertical: 4,
              horizontal: widget.nested ? 0 : 8,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: widget.nested ? 16 : 14,
              vertical: 11,
            ),
            decoration: BoxDecoration(
              gradient: widget.selected ? selectedGradient : null,
              color: widget.selected
                  ? null
                  : (_isHovered ? hoverColor : Colors.transparent),
              borderRadius: BorderRadius.circular(16),
              border: widget.selected
                  ? Border.all(color: activeColor.withOpacity(0.2), width: 1)
                  : Border.all(color: Colors.transparent, width: 1),
              boxShadow: widget.selected
                  ? [
                      BoxShadow(
                        color: activeColor.withOpacity(0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    widget.icon,
                    key: ValueKey(widget.selected),
                    size: 22,
                    color: widget.selected
                        ? activeColor
                        : (_isHovered ? widget.textPrimary : inactiveColor),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      color: widget.selected
                          ? activeColor
                          : (_isHovered
                                ? widget.textPrimary
                                : widget.textPrimary.withOpacity(0.8)),
                      fontWeight: widget.selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontSize: 14,
                      fontFamily: 'Inter',
                      letterSpacing: widget.selected ? -0.2 : 0,
                    ),
                    child: Text(widget.label),
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
                if (widget.selected && widget.trailing == null)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: activeColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: activeColor.withOpacity(0.5),
                          blurRadius: 6,
                        ),
                      ],
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
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(a1),
        child: child,
      );
    },
  ).then((_) {
    _AppNavState._isOpen = false;
  });
}

class _AppNavState {
  static bool _isOpen = false;
}

class EdgeNavHandle extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) =>
          showAppSidebar(context, user: user, currentRoute: currentRoute),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () =>
            showAppSidebar(context, user: user, currentRoute: currentRoute),
        child: Container(
          width: width,
          color: Colors.transparent, // Hit area
          child: showIndicator
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
