import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/analisis_service.dart';
import '../../models/analisis_models.dart';

class ProjectTransactionsDialog extends StatefulWidget {
  final String idxiaomi;
  final String? projectName;

  const ProjectTransactionsDialog({
    super.key,
    required this.idxiaomi,
    this.projectName,
  });

  @override
  State<ProjectTransactionsDialog> createState() =>
      _ProjectTransactionsDialogState();
}

class _ProjectTransactionsDialogState extends State<ProjectTransactionsDialog> {
  final _analisisService = const AnalisisService();
  List<Transaction> _transactions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    try {
      final data = await _analisisService.getTransactions(widget.idxiaomi);
      if (mounted) {
        setState(() {
          _transactions = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    String clean = s.trim().replaceAll(',', '');
    clean = clean
        .replaceAll('AM', ' AM')
        .replaceAll('PM', ' PM')
        .replaceAll('  ', ' ');
    final iso = DateTime.tryParse(clean);
    if (iso != null) return iso;
    final formats = [
      'MMM d yyyy h:mm a',
      'MMMM d yyyy h:mm a',
      'd/M/yyyy',
      'dd/MM/yyyy',
      'MMM d yyyy HH:mm',
      'yyyy-MM-dd',
      'yyyy-MM-dd HH:mm:ss',
    ];
    for (final format in formats) {
      try {
        return DateFormat(format, 'en_US').parse(clean);
      } catch (_) {
        try {
          return DateFormat(format, 'es_ES').parse(clean);
        } catch (_) {}
      }
    }
    return null;
  }

  String _formatDate(String? s) {
    if (s == null || s.isEmpty || s == 'N/A' || s == '-') return 'Fecha Desconocida';
    final d = _parseDate(s);
    if (d == null) return s!;
    if (d.hour == 0 && d.minute == 0) {
      return DateFormat('dd/MM/yyyy').format(d);
    }
    return DateFormat('dd/MM/yyyy HH:mm').format(d);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.projectName ?? widget.idxiaomi,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Historial de Transacciones',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
          style: IconButton.styleFrom(
            backgroundColor: Colors.grey.shade100,
            hoverColor: Colors.grey.shade200,
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              'Error al cargar transacciones',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (_transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No se encontraron transacciones',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildSummary(),
        const SizedBox(height: 20),
        Expanded(
          child: ListView.separated(
            itemCount: _transactions.length,
            separatorBuilder: (ctx, i) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) => _buildTransactionCard(_transactions[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildSummary() {
    final totalCost = _transactions.fold(0.0, (sum, t) => sum + (t.cost ?? 0));
    final currencyFormat = NumberFormat.currency(symbol: '€', locale: 'es_ES');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          _buildSummaryItem(
            'Gasto Total',
            currencyFormat.format(totalCost),
            Icons.euro,
            Colors.green,
          ),
          Container(
            height: 40,
            width: 1,
            color: Colors.grey.shade300,
            margin: const EdgeInsets.symmetric(horizontal: 24),
          ),
          _buildSummaryItem(
            'Transacciones',
            _transactions.length.toString(),
            Icons.receipt,
            Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C3E50),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTransactionCard(Transaction t) {
    final currencyFormat = NumberFormat.currency(symbol: '€', locale: 'es_ES');
    final dateStr = _formatDate(t.fechaf ?? t.fechai);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEBF5FB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.shopping_bag_outlined,
              color: Color(0xFF3498DB),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        t.descripcion ?? 'Sin Descripción',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                    ),
                    Text(
                      currencyFormat.format(t.cost ?? 0),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.person_outline,
                      size: 16,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      t.user ?? 'Usuario Desconocido',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 16,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${t.unit ?? 0} uds',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const Spacer(),
                    // Payment Toggle for Admin/Chief
                    Builder(
                      builder: (context) {
                        final user = Provider.of<ApiService>(
                          context,
                          listen: false,
                        ).currentUser;
                        if (user != null &&
                            (user.role == 'admin' || user.role == 'chief')) {
                          return InkWell(
                            onTap: () async {
                              try {
                                await _analisisService.togglePaymentStatus(
                                  t.id!,
                                  !(t.paid ?? false),
                                );
                                if (!context.mounted) return;
                                _loadTransactions();
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (t.paid == true
                                            ? Colors.green
                                            : Colors.orange)
                                        .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color:
                                      (t.paid == true
                                              ? Colors.green
                                              : Colors.orange)
                                          .withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    t.paid == true
                                        ? Icons.check_circle_rounded
                                        : Icons.pending_rounded,
                                    color: t.paid == true
                                        ? Colors.green
                                        : Colors.orange,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    t.paid == true ? 'PAGADO' : 'NO PAGADO',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: t.paid == true
                                          ? Colors.green
                                          : Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'ID: ${t.id}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontFamily: 'Monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
