import 'package:flutter/material.dart';
import '../../models/agent_models.dart';

class AgentDecisionPanel extends StatelessWidget {
  final LatestLLM? latestLLM;
  final VoidCallback? onRunAgent;

  const AgentDecisionPanel({super.key, this.latestLLM, this.onRunAgent});

  @override
  Widget build(BuildContext context) {
    if (latestLLM == null) {
      return Center(
        child: Column(
          children: [
            const Icon(Icons.psychology_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Sin Análisis IA aún'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRunAgent,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Ejecutar Análisis del Agente'),
            ),
          ],
        ),
      );
    }

    final llm = latestLLM!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildConfidenceSection(context, llm.confidence),
        const SizedBox(height: 24),
        _buildSectionHeader(context, 'Requisitos Extraídos', Icons.list_alt),
        _buildJsonViewer(context, llm.extractedRequirements),
        const SizedBox(height: 24),
        if (llm.blockers.isNotEmpty) ...[
          _buildSectionHeader(
            context,
            'Bloqueos',
            Icons.warning_amber_rounded,
            color: Colors.redAccent,
          ),
          ...llm.blockers.map((b) => _buildBlockerItem(b)),
          const SizedBox(height: 24),
        ],
        _buildSectionHeader(
          context,
          'Acciones Sugeridas',
          Icons.lightbulb_outline,
          color: Colors.amber,
        ),
        ...llm.suggestedActions.map((a) => _buildActionItem(a)),
        if (llm.suggestedAssignees.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildSectionHeader(
            context,
            'Personas Sugeridas',
            Icons.people_alt_outlined,
            color: Colors.blueAccent,
          ),
          ...llm.suggestedAssignees.map((p) => _buildAssigneeItem(p)),
        ],
      ],
    );
  }

  Widget _buildAssigneeItem(String person) {
    return Padding(
      padding: const EdgeInsets.only(left: 28.0, bottom: 8.0),
      child: Row(
        children: [
          const Icon(Icons.person, size: 16, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(child: Text(person)),
        ],
      ),
    );
  }

  Widget _buildConfidenceSection(BuildContext context, double confidence) {
    final theme = Theme.of(context);
    final percentage = (confidence * 100).toInt();
    Color color;
    if (confidence >= 0.8) {
      color = Colors.green;
    } else if (confidence >= 0.5)
      color = Colors.orange;
    else
      color = Colors.red;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Puntuación de Confianza IA',
                style: theme.textTheme.titleMedium,
              ),
              Text(
                '$percentage%',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: confidence,
            backgroundColor: color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
          ),
          const SizedBox(height: 8),
          Text(
            confidence >= 0.8
                ? 'Alta Confianza. Listo para acción automática.'
                : 'Baja Confianza. Requiere revisión humana.',
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon, {
    Color? color,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Icon(icon, color: color ?? theme.colorScheme.primary, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJsonViewer(BuildContext context, Map<String, dynamic> data) {
    if (data.isEmpty) return const Text('No se extrajeron requisitos.');
    // Simple key-value list for now
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.black12,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: data.entries.map((e) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.key}: ',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value.toString(),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBlockerItem(String text) {
    return Card(
      color: Colors.red.withOpacity(0.1),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.block, color: Colors.red),
        title: Text(text, style: const TextStyle(color: Colors.redAccent)),
        dense: true,
      ),
    );
  }

  Widget _buildActionItem(String text) {
    return Card(
      color: Colors.amber.withOpacity(0.1),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.arrow_forward, color: Colors.amber),
        title: Text(text),
        dense: true,
      ),
    );
  }
}
