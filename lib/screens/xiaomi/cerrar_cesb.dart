import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/xiaomi_provider.dart';
import '../../widgets/main_sidebar.dart';

class CerrarCesbScreen extends StatefulWidget {
  final String? initialCesb;
  final bool isEmbedded;
  const CerrarCesbScreen({
    super.key,
    this.initialCesb,
    this.isEmbedded = false,
  });

  @override
  State<CerrarCesbScreen> createState() => _CerrarCesbScreenState();
}

class _CerrarCesbScreenState extends State<CerrarCesbScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _cesbController = TextEditingController();
  final FocusNode _cesbFocus = FocusNode();

  XiaomiTeam? _selectedTeam;
  bool _submitting = false;
  OverlayEntry? _edgeOverlay;

  @override
  void dispose() {
    _cesbController.dispose();
    _cesbFocus.dispose();
    _edgeOverlay?.remove();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialCesb != null) {
      _cesbController.text = widget.initialCesb!;
    }
    
    // Initialize teams
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<XiaomiProvider>().initTeams();
      
      if (!mounted) return;
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
                  user: Provider.of<ApiService>(ctx, listen: false).currentUser,
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
    });
  }

  bool get _isSupervisor {
    final role = context.read<ApiService>().currentUser?.role?.toLowerCase();
    return role == 'admin' || role == 'chief' || role == 'clerc' || role == 'technitian';
  }

  Future<void> _confirmAndSend() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTeam == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona un equipo.')),
      );
      return;
    }

    final cesb = _cesbController.text.trim();

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar'),
        content: Text('¿Quieres cerrar el CESB "$cesb" con el equipo ${_selectedTeam!.nombre}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    setState(() => _submitting = true);
    try {
      final api = ApiService.instance?.client;
      if (api == null) throw Exception('API client not available');

      final payload = <String, dynamic>{
        'cesb': cesb,
        'team_id': _selectedTeam!.id,
      };

      final resp = await api.post('/xiaomieco/cerrar_cesb', jsonBody: payload);

      if (!mounted) return;

      if (resp.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CESB cerrado con éxito.')),
        );
        _cesbController.clear();
        setState(() => _selectedTeam = null);
        _cesbFocus.requestFocus();
      } else {
        final err = resp.body ?? resp.error ?? 'Error';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $err')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final xiaomi = context.watch<XiaomiProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cerrar CESB (Xiaomi ECO)'),
        automaticallyImplyLeading: false,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primaryContainer.withOpacity(0.4),
                  theme.scaffoldBackgroundColor,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          if (xiaomi.isLoading && !xiaomi.isInitialized)
            const Center(child: CircularProgressIndicator())
          else
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (xiaomi.initStatus == 'missing')
                        _buildInitMissing(xiaomi)
                      else
                        _buildMainForm(xiaomi, theme),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInitMissing(XiaomiProvider xiaomi) {
    final theme = Theme.of(context);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.group_off_rounded, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'No hay equipos creados para hoy',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _isSupervisor 
                ? 'Como supervisor, puedes crear nuevos equipos o clonar los de ayer.'
                : 'Por favor, solicita a un supervisor (Admin/Chief) que cree los equipos del día.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.hintColor),
            ),
            if (_isSupervisor) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (xiaomi.yesterdayTeams.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: () => xiaomi.cloneTeams(),
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Usar Equipos de Ayer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.secondary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showTeamDialog(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Crear Nuevo Equipo'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMainForm(XiaomiProvider xiaomi, ThemeData theme) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _cesbController,
                focusNode: _cesbFocus,
                decoration: const InputDecoration(
                  labelText: 'CESB',
                  prefixIcon: Icon(Icons.qr_code_scanner_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v?.isEmpty ?? true) ? 'Requerido' : null,
              ),
              const SizedBox(height: 20),
              
              const Text(
                'Seleccionar Equipo:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              if (xiaomi.todayTeams.isEmpty)
                const Text('No hay equipos disponibles', style: TextStyle(color: Colors.red))
              else
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: xiaomi.todayTeams.map((t) {
                    final isSelected = _selectedTeam?.id == t.id;
                    final color = _getColorFromName(t.nombre);
                    return SizedBox(
                      width: 100,
                      height: 100,
                      child: Stack(
                        children: [
                          InkWell(
                            onTap: () => setState(() => _selectedTeam = t),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected ? color : theme.dividerColor,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 20, height: 20,
                                      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      t.nombre,
                                      style: TextStyle(
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        fontSize: 15,
                                        color: isSelected ? color : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (_isSupervisor)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: IconButton(
                                icon: const Icon(Icons.edit_rounded, size: 16),
                                onPressed: () => _showTeamDialog(team: t),
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              
              if (_selectedTeam != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Miembros del equipo:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: _selectedTeam!.members.map((m) => Chip(
                          label: Text(m, style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: _getColorFromName(_selectedTeam!.nombre).withOpacity(0.1),
                        )).toList(),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _confirmAndSend,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting 
                    ? const CircularProgressIndicator()
                    : const Text('CERRAR CESB', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              if (_isSupervisor) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => _showTeamDialog(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Agregar otro equipo'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTeamDialog({XiaomiTeam? team}) async {
    final isEditing = team != null;
    final List<String> colors = ['Rojo', 'Azul', 'Verde', 'Amarillo', 'Naranja', 'Morado', 'Rosa', 'Marrón', 'Gris', 'Negro'];
    String? selectedColor = isEditing ? team.nombre : colors[0];
    List<Map<String, dynamic>> allUsers = [];
    List<String> selectedUsernames = isEditing ? List.from(team.members) : [];
    String searchQuery = '';
    bool loadingUsers = true;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (loadingUsers) {
            ApiService.instance?.client.get('/empleados/').then((res) {
              if (res.ok && res.body is List) {
                final users = List<Map<String, dynamic>>.from(res.body)
                    .where((u) => u['activo'] == true || u['activo'] == 1)
                    .toList();
                // Sort users alphabetically by name
                users.sort((a, b) => (a['nombre'] ?? '').toString().compareTo((b['nombre'] ?? '').toString()));
                allUsers = users;
                setDialogState(() => loadingUsers = false);
              }
            });
            return const Center(child: CircularProgressIndicator());
          }

          final xiaomi = context.watch<XiaomiProvider>();
          final existing = xiaomi.todayTeams.cast<XiaomiTeam?>().firstWhere(
            (t) => t?.nombre == selectedColor,
            orElse: () => null,
          );
          final effectiveEditing = isEditing || existing != null;
          final targetTeamId = existing?.id ?? (isEditing ? team.id : null);

          return AlertDialog(
            title: Text(effectiveEditing ? 'Editar Equipo' : 'Crear Equipo'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Color del Equipo:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: colors.map((c) {
                      final isSelected = selectedColor == c;
                      final col = _getColorFromName(c);
                      return ChoiceChip(
                        label: Text(c),
                        selected: isSelected,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        selectedColor: col.withOpacity(0.3),
                        labelStyle: TextStyle(
                          color: isSelected ? col : null,
                          fontSize: 15,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                        onSelected: (v) {
                          if (v) {
                            setDialogState(() {
                              selectedColor = c;
                              // Sync members if team already exists for this color
                              final xiaomi = context.read<XiaomiProvider>();
                              final existing = xiaomi.todayTeams.cast<XiaomiTeam?>().firstWhere(
                                (t) => t?.nombre == c,
                                orElse: () => null,
                              );
                              if (existing != null) {
                                selectedUsernames = List.from(existing.members);
                              } else if (!isEditing) {
                                selectedUsernames = [];
                              }
                            });
                          }
                        },
                        avatar: CircleAvatar(backgroundColor: col, radius: 8),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  const Text('Seleccionar Miembros:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                    ),
                    onChanged: (v) => setDialogState(() => searchQuery = v.toLowerCase()),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Builder(
                      builder: (context) {
                        final xiaomi = context.watch<XiaomiProvider>();
                        Map<String, String> assignedUsers = {};
                        for (var t in xiaomi.todayTeams) {
                          if (t.nombre != selectedColor) {
                            for (var m in t.members) {
                              assignedUsers[m] = t.nombre;
                            }
                          }
                        }

                        final filtered = allUsers.where((u) {
                          final n = '${u['nombre']} ${u['apellido']}'.toLowerCase();
                          return n.contains(searchQuery);
                        }).toList();

                        if (filtered.isEmpty && !loadingUsers) {
                          return const Center(child: Text('Sin resultados', style: TextStyle(color: Colors.grey)));
                        }

                        return ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final u = filtered[i];
                            final username = u['usuario'] ?? u['username'] ?? '';
                            final isSelected = selectedUsernames.contains(username);
                            final assignedTeam = assignedUsers[username];
                            final isUnavailable = assignedTeam != null;

                            return CheckboxListTile(
                              enabled: !isUnavailable,
                              title: Text('${u['nombre']} ${u['apellido']}', 
                                style: TextStyle(color: isUnavailable ? Colors.grey : null)
                              ),
                              subtitle: isUnavailable
                                ? Text('Ya en equipo $assignedTeam', style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold))
                                : Text(u['puesto'] ?? 'Operador', style: const TextStyle(fontSize: 12)),
                              value: isSelected,
                              onChanged: (v) {
                                if (isUnavailable) return;
                                setDialogState(() {
                                  if (v == true) {
                                    selectedUsernames.add(username);
                                  } else {
                                    selectedUsernames.remove(username);
                                  }
                                });
                              },
                            );
                          },
                        );

                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx), 
                child: const Text('Cancelar')
              ),
              ElevatedButton(
                onPressed: saving ? null : () async {
                  if (selectedUsernames.isEmpty) {
                    if (!effectiveEditing) return;
                    
                    final confirm = await showDialog<bool>(
                      context: ctx,
                      builder: (c) => AlertDialog(
                        title: const Text('Eliminar Equipo'),
                        content: const Text('Has desmarcado a todos los miembros. ¿Quieres ELIMINAR este equipo?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sí, eliminar')),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                  }

                  setDialogState(() => saving = true);
                  try {
                    bool success = false;
                    if (effectiveEditing && targetTeamId != null) {
                      success = await xiaomi.updateTeam(targetTeamId, selectedColor!, selectedUsernames);
                    } else {
                      success = await xiaomi.createTeam(selectedColor!, selectedUsernames);
                    }
                    
                    if (success) {
                      if (effectiveEditing && selectedUsernames.isEmpty && targetTeamId != null) {
                        if (_selectedTeam?.id == targetTeamId) {
                          setState(() => _selectedTeam = null);
                        }
                      }
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    }
                  } finally {
                    if (ctx.mounted) setDialogState(() => saving = false);
                  }
                },
                child: saving 
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(effectiveEditing ? 'ACTUALIZAR' : 'CREAR'),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _getColorFromName(String name) {
    switch (name.toLowerCase()) {
      case 'rojo': return Colors.red;
      case 'azul': return Colors.blue;
      case 'verde': return Colors.green;
      case 'amarillo': return Colors.yellow;
      case 'naranja': return Colors.orange;
      case 'morado': return Colors.purple;
      case 'rosa': return Colors.pink;
      case 'marrón': return Colors.brown;
      case 'gris': return Colors.grey;
      case 'negro': return Colors.black;
      default: return Colors.blueGrey;
    }
  }
}
