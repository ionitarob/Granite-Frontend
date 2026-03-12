import 'package:flutter/material.dart';
import '../../models/analisis_models.dart';

class AysFilteredDataDialog extends StatefulWidget {
  final List<Transaction> transactions;
  final String title;

  const AysFilteredDataDialog({
    super.key,
    required this.transactions,
    required this.title,
  });

  @override
  State<AysFilteredDataDialog> createState() => _AysFilteredDataDialogState();
}

class _AysFilteredDataDialogState extends State<AysFilteredDataDialog> {
  late List<Transaction> _sortedTransactions;
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _sortedTransactions = List.from(widget.transactions);
  }

  void _onSort(int columnIndex, bool ascending) {
    if (_sortColumnIndex == columnIndex && ascending && !_sortAscending) {
      // Cycle: Asc -> Desc -> Normal
      setState(() {
        _sortColumnIndex = null;
        _sortAscending = true;
        _sortedTransactions = List.from(widget.transactions);
      });
      return;
    }

    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;

      _sortedTransactions.sort((a, b) {
        dynamic valA;
        dynamic valB;

        switch (columnIndex) {
          case 0: // ID
            valA = a.id ?? 0;
            valB = b.id ?? 0;
            break;
          case 1: // CSKU
            valA = a.csku ?? '';
            valB = b.csku ?? '';
            break;
          case 2: // Servicio
            valA = a.servicio ?? '';
            valB = b.servicio ?? '';
            break;
          case 3: // Fabricante
            valA = a.fabricante ?? '';
            valB = b.fabricante ?? '';
            break;
          case 4: // Cliente
            valA = a.cliente ?? '';
            valB = b.cliente ?? '';
            break;
          case 5: // ID Xiaomi
            valA = a.idxiaomi ?? '';
            valB = b.idxiaomi ?? '';
            break;
          case 8: // Fecha F
            valA = a.fechaf ?? '';
            valB = b.fechaf ?? '';
            break;
          case 9: // Coste
            valA = a.cost ?? 0.0;
            valB = b.cost ?? 0.0;
            break;
          case 10: // Pago
            valA = (a.paid ?? false) ? 1 : 0;
            valB = (b.paid ?? false) ? 1 : 0;
            break;
          default:
            valA = '';
            valB = '';
        }

        if (ascending) {
          return Comparable.compare(valA, valB);
        } else {
          return Comparable.compare(valB, valA);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: size.width * 0.9,
        constraints: BoxConstraints(maxHeight: size.height * 0.85),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_sortedTransactions.length} registros encontrados',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const Divider(height: 32),
            Expanded(
              child: _sortedTransactions.isEmpty
                  ? const Center(child: Text('No hay datos.'))
                  : Theme(
                      data: theme.copyWith(
                        dividerColor: Colors.transparent, // cleaner look
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            sortColumnIndex: _sortColumnIndex,
                            sortAscending: _sortAscending,
                            headingRowHeight: 48,
                            dataRowMinHeight: 48,
                            dataRowMaxHeight: 56,
                            headingRowColor: WidgetStateProperty.all(
                              theme.primaryColor.withOpacity(0.05),
                            ),
                            columns: [
                              DataColumn(
                                label: const Text('ID'),
                                onSort: _onSort,
                              ),
                              DataColumn(
                                label: const Text('CSKU'),
                                onSort: _onSort,
                              ),
                              DataColumn(
                                label: const Text('Servicio'),
                                onSort: _onSort,
                              ),
                              DataColumn(
                                label: const Text('Fabricante'),
                                onSort: _onSort,
                              ),
                              DataColumn(
                                label: const Text('Cliente'),
                                onSort: _onSort,
                              ),
                              DataColumn(
                                label: const Text('ID Xiaomi'),
                                onSort: _onSort,
                              ),
                              const DataColumn(label: Text('Descripción')),
                              const DataColumn(label: Text('Unid.')),
                              DataColumn(
                                label: const Text('Fecha F'),
                                onSort: _onSort,
                              ),
                              DataColumn(
                                label: const Text('Coste'),
                                onSort: _onSort,
                                numeric: true,
                              ),
                              DataColumn(
                                label: const Text('Estado Pago'),
                                onSort: _onSort,
                              ),
                            ],
                            rows: _sortedTransactions.map((t) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(t.id?.toString() ?? '-')),
                                  DataCell(Text(t.csku ?? '-')),
                                  DataCell(Text(t.servicio ?? '-')),
                                  DataCell(Text(t.fabricante ?? '-')),
                                  DataCell(Text(t.cliente ?? '-')),
                                  DataCell(Text(t.idxiaomi ?? '-')),
                                  DataCell(
                                    SizedBox(
                                      width: 200,
                                      child: Text(
                                        t.descripcion ?? '-',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(t.unit ?? '-')),
                                  DataCell(Text(t.fechaf ?? '-')),
                                  DataCell(
                                    Text(t.cost?.toStringAsFixed(2) ?? '0.00'),
                                  ),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: (t.paid ?? false)
                                            ? Colors.green.withOpacity(0.1)
                                            : Colors.orange.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        (t.paid ?? false)
                                            ? 'PAGADO'
                                            : 'PENDIENTE',
                                        style: TextStyle(
                                          color: (t.paid ?? false)
                                              ? Colors.green
                                              : Colors.orange,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
