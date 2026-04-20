import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import '../services/orderops_service.dart';
import 'printer_selection_dialog.dart';
import '../models/agent_models.dart';

class PdfPreviewDialog extends StatefulWidget {
  final Uint8List pdfBytes;
  final String fileName;
  final OrderOpsService service;

  const PdfPreviewDialog({
    super.key,
    required this.pdfBytes,
    required this.fileName,
    required this.service,
  });

  @override
  State<PdfPreviewDialog> createState() => _PdfPreviewDialogState();
}

class _PdfPreviewDialogState extends State<PdfPreviewDialog> {
  bool _isPrinting = false;

  Future<void> _downloadPdf(BuildContext context) async {
    try {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar Acta',
        fileName: widget.fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsBytes(widget.pdfBytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Archivo guardado correctamente')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    }
  }

  Future<void> _printPdf(BuildContext context) async {
    final printer = await showDialog<AgentPrinter>(
      context: context,
      builder: (context) => PrinterSelectionDialog(service: widget.service),
    );

    if (printer != null) {
      setState(() => _isPrinting = true);
      try {
        // Direct print via backend to bypass UI freeze and use the selected network IP
        final result = await widget.service.directPrintPdf(printer.ip, widget.pdfBytes);
        
        if (mounted) {
          if (result.ok) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Documento enviado a ${printer.name} (${printer.ip})'),
                backgroundColor: Colors.green.shade800,
              ),
            );
          } else {
            // Fallback to system dialog if direct print fails or if user cancels
            final error = result.error ?? 'Error desconocido';
            debugPrint('[PdfPreview] Direct print failed: $error. Falling back to system dialog.');
            
            await Printing.layoutPdf(
              onLayout: (PdfPageFormat format) async => widget.pdfBytes,
              name: widget.fileName,
            );
          }
        }
      } catch (e) {
        debugPrint('[PdfPreview] Error during print: $e');
        if (mounted) {
          // Fallback to system dialog on exception
          await Printing.layoutPdf(
            onLayout: (PdfPageFormat format) async => widget.pdfBytes,
            name: widget.fileName,
          );
        }
      } finally {
        if (mounted) setState(() => _isPrinting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: Column(
        children: [
          AppBar(
            title: Text(widget.fileName),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: _isPrinting ? null : () => _downloadPdf(context),
                tooltip: 'Descargar/Guardar',
              ),
              IconButton(
                icon: const Icon(Icons.print),
                onPressed: _isPrinting ? null : () => _printPdf(context),
                tooltip: 'Imprimir',
              ),
            ],
          ),
          Expanded(
            child: SfPdfViewer.memory(
              widget.pdfBytes,
              canShowScrollHead: true,
              canShowScrollStatus: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isPrinting ? null : () => _printPdf(context),
                  icon: _isPrinting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print),
                  label: Text(_isPrinting ? 'Imprimiendo...' : 'Imprimir Ahora'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
