import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../widgets/animated_background.dart';

class TvHistoryScreen extends StatefulWidget {
  const TvHistoryScreen({super.key});

  @override
  State<TvHistoryScreen> createState() => _TvHistoryScreenState();
}

class _TvHistoryScreenState extends State<TvHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _historial = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await api.client.get('/tv/revisions/');
      
      if (res.ok) {
        setState(() {
          _historial = res.body as List<dynamic>;
          _loading = false;
        });
      } else {
        throw Exception(res.error ?? 'Error al cargar el historial');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial Revisión TV'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Stack(
        children: [
          const AnimatedBackgroundWidget(intensity: 0.2),
          _loading 
            ? const Center(child: CircularProgressIndicator())
            : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
              : _historial.isEmpty
                ? const Center(child: Text('No hay revisiones registradas'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _historial.length,
                    itemBuilder: (context, index) {
                      final item = _historial[index];
                      return _buildHistoryCard(item);
                    },
                  ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(dynamic item) {
    final date = DateTime.tryParse(item['created_at'] ?? '')?.toLocal();
    final dateStr = date != null ? DateFormat('dd/MM/yyyy HH:mm').format(date) : '-';
    final pNum = item['part_number'] ?? 'N/A';
    final sNum = item['serial_number'] ?? 'N/A';
    final estado = item['estado'] ?? 'Desconocido';
    final id = item['id'];
    
    final api = Provider.of<ApiService>(context, listen: false);
    final imageUrl = '${api.client.baseUrl}/tv/revisions/$id/image/';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showDetailDialog(item, imageUrl),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image preview
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    imageUrl,
                    headers: api.client.accessToken != null 
                        ? {'Authorization': 'Bearer ${api.client.accessToken}'}
                        : null,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_not_supported, color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Text info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$pNum | $sNum', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('Estado: $estado', style: TextStyle(color: _getEstadoColor(estado), fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text('Fecha: $dateStr', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text('Usuario: ${item['usuario'] ?? 'Anon'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Color _getEstadoColor(String estado) {
    if (estado == 'Correcto') return Colors.green;
    if (estado == 'Defectuoso') return Colors.red;
    return Colors.orange;
  }

  void _showDetailDialog(dynamic item, String imageUrl) {
    final api = Provider.of<ApiService>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Detalle: ${item['serial_number']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.network(
                imageUrl,
                headers: api.client.accessToken != null 
                    ? {'Authorization': 'Bearer ${api.client.accessToken}'}
                    : null,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_not_supported, size: 100),
              ),
              const SizedBox(height: 16),
              _buildDetailInfo('Part Number', item['part_number']),
              _buildDetailInfo('EAN', item['ean']),
              _buildDetailInfo('Sticker', item['sticker']),
              _buildDetailInfo('Pulgadas', item['pulgadas']),
              _buildDetailInfo('Comentarios', item['comentarios']),
              _buildDetailInfo('Chequeo Visual', item['chequeo_visual'] == true ? 'SÍ' : 'NO'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _buildDetailInfo(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value?.toString() ?? '-')),
        ],
      ),
    );
  }
}
