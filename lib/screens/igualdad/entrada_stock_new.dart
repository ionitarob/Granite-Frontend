
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../src/api/igualdad_api.dart';
import '../../widgets/main_sidebar.dart';

class EntradaStockNewScreen extends StatefulWidget {
	const EntradaStockNewScreen({super.key});

	@override
	State<EntradaStockNewScreen> createState() => _EntradaStockNewScreenState();
}

class _EntradaStockNewScreenState extends State<EntradaStockNewScreen> {
	final FocusNode _focusRoot = FocusNode();
	String? _selectedSource;
	String? _pickedFileName;
	bool _dragActive = false;
	bool _hasExtras = false;
	int _botonesCount = 0;
	int _powerbanksCount = 0;
	bool _submitting = false;
	final TextEditingController _numeroPedidoController = TextEditingController();
	final TextEditingController _numSeController = TextEditingController();
	final TextEditingController _resumenCategoriaController = TextEditingController();
	final TextEditingController _referenciaEnvioController = TextEditingController();
	final TextEditingController _observacionesController = TextEditingController();
	Map<String, dynamic>? _importResult;
	bool _submitAttempted = false;
	bool _updateResumen = true;
	Uint8List? _csvBytes;

	String get _numeroPedido => _numeroPedidoController.text.trim();

	@override
	void initState() {
		super.initState();
		_numeroPedidoController.addListener(_onNumeroPedidoChanged);
	}

	@override
	void dispose() {
		_numeroPedidoController.removeListener(_onNumeroPedidoChanged);
		_numeroPedidoController.dispose();
		_numSeController.dispose();
		_resumenCategoriaController.dispose();
		_referenciaEnvioController.dispose();
		_observacionesController.dispose();
		_focusRoot.dispose();
		super.dispose();
	}

	void _onNumeroPedidoChanged() {
		if (!mounted) return;
		setState(() {
			if (_submitAttempted && _numeroPedido.isNotEmpty) {
				_submitAttempted = false;
			}
		});
	}

	Future<void> _pickCsv() async {
		try {
			final result = await FilePicker.platform.pickFiles(
				type: FileType.custom,
				allowedExtensions: const ['csv'],
				withData: true,
			);
			if (!mounted) return;
			if (result != null && result.files.isNotEmpty) {
				await _handleCsvSelected(result.files.first);
			}
		} catch (e) {
			// keep UI responsive even if file picker fails
			if (!mounted) return;
			ScaffoldMessenger.of(context).showSnackBar(
				SnackBar(content: Text('No se pudo seleccionar el archivo: $e')),
			);
		}
	}

	Future<void> _handleCsvSelected(PlatformFile file) async {
		if (file.bytes == null) {
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(content: Text('No se pudieron leer los datos del CSV seleccionado.')),
			);
			return;
		}
		final normalized = _basename(file.name);
		setState(() {
			_pickedFileName = normalized;
			_importResult = null;
			_csvBytes = file.bytes;
		});
		final guessNumero = _guessNumeroPedido(normalized);
		if (guessNumero != null && _numeroPedido.isEmpty) {
			_numeroPedidoController.text = guessNumero;
			if (_numSeController.text.trim().isEmpty) {
				_numSeController.text = guessNumero;
			}
		}
		final extras = await _askExtrasDialog();
		if (!mounted) return;
		if (extras == null) {
			setState(() {
				_pickedFileName = null;
				_hasExtras = false;
				_botonesCount = 0;
				_powerbanksCount = 0;
				_importResult = null;
				_csvBytes = null;
			});
			_numeroPedidoController.clear();
			_numSeController.clear();
			return;
		}
		final (bool includes, int botones, int powerbanks) = extras;
		setState(() {
			_hasExtras = includes;
			_botonesCount = includes ? botones : 0;
			_powerbanksCount = includes ? powerbanks : 0;
		});
	}

	Future<(bool includes, int botones, int powerbanks)?> _askExtrasDialog() async {
		final formKey = GlobalKey<FormState>();
		bool includesExtras = _hasExtras;
		final botonesController = TextEditingController(
			text: _botonesCount > 0 ? _botonesCount.toString() : '',
		);
		final powerbanksController = TextEditingController(
			text: _powerbanksCount > 0 ? _powerbanksCount.toString() : '',
		);
		final result = await showDialog<(bool, int, int)?>(
			context: context,
			barrierDismissible: false,
			builder: (dialogContext) {
				return StatefulBuilder(
					builder: (ctx, setStateDialog) {
						return AlertDialog(
								title: const Text('Dispositivos adicionales'),
								content: Form(
									key: formKey,
									child: SingleChildScrollView(
										child: Column(
											mainAxisSize: MainAxisSize.min,
											crossAxisAlignment: CrossAxisAlignment.start,
											children: [
												const Text('Por favor indique si hay botones o powerbanks incluidos en este SE.'),
												const SizedBox(height: 12),
												SwitchListTile.adaptive(
													title: const Text('Sí, hay dispositivos adicionales'),
													subtitle: const Text('Botones y/o powerbanks'),
													value: includesExtras,
													onChanged: (value) {
														setStateDialog(() {
															includesExtras = value;
														});
													},
												),
												if (includesExtras) ...[
													const SizedBox(height: 8),
													TextFormField(
														controller: botonesController,
														keyboardType: TextInputType.number,
														inputFormatters: [FilteringTextInputFormatter.digitsOnly],
														decoration: const InputDecoration(
															labelText: 'Cantidad de botones',
															border: OutlineInputBorder(),
														),
														validator: (value) {
															if (!includesExtras) return null;
															if (value == null || value.isEmpty) {
																return 'Indica un número';
															}
															if (int.tryParse(value) == null) {
																return 'Solo dígitos';
															}
															return null;
														},
													),
													const SizedBox(height: 12),
													TextFormField(
														controller: powerbanksController,
														keyboardType: TextInputType.number,
														inputFormatters: [FilteringTextInputFormatter.digitsOnly],
														decoration: const InputDecoration(
															labelText: 'Cantidad de powerbanks',
															border: OutlineInputBorder(),
														),
														validator: (value) {
															if (!includesExtras) return null;
															if (value == null || value.isEmpty) {
																return 'Indica un número';
															}
															if (int.tryParse(value) == null) {
																return 'Solo dígitos';
															}
															return null;
														},
													),
												],
											],
										),
									),
								),
								actions: [
									TextButton(
										onPressed: () => Navigator.of(ctx).pop(null),
										child: const Text('Cancelar'),
									),
									FilledButton(
										onPressed: () {
											if (includesExtras && !(formKey.currentState?.validate() ?? false)) {
												return;
											}
												final botonesText = botonesController.text.trim();
												final powerbanksText = powerbanksController.text.trim();
												final botones = includesExtras ? int.parse(botonesText) : 0;
												final powerbanks = includesExtras ? int.parse(powerbanksText) : 0;
											Navigator.of(ctx).pop((includesExtras, botones, powerbanks));
										},
										child: const Text('Confirmar'),
									),
								],
							);
						},
					);
				});
		WidgetsBinding.instance.addPostFrameCallback((_) {
			botonesController.dispose();
			powerbanksController.dispose();
		});
		return result;
	}

	void _handleDrop() {
		ScaffoldMessenger.of(context).showSnackBar(
			const SnackBar(content: Text('Para adjuntar el CSV utiliza el botón "Buscar CSV".')),
		);
	}

	Future<void> _submitBatch() async {
		if (_selectedSource == null) {
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(content: Text('Selecciona un origen antes de continuar.')),
			);
			return;
		}
		if (_pickedFileName == null) {
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(content: Text('Carga un archivo CSV antes de continuar.')),
			);
			return;
		}
		if (_csvBytes == null) {
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(content: Text('No se han podido leer los datos del CSV. Vuelve a seleccionarlo.')),
			);
			return;
		}
		if (_numeroPedido.isEmpty) {
			setState(() => _submitAttempted = true);
			ScaffoldMessenger.of(context).showSnackBar(
				const SnackBar(content: Text('Introduce el número de orden para continuar.')),
			);
			return;
		}
		FocusScope.of(context).unfocus();
		setState(() => _submitting = true);
		try {
			final payload = <String, dynamic>{
				'numero_pedido': _numeroPedido,
				'source': _selectedSource,
				'update_resumen': _updateResumen,
				'botones': _botonesCount,
				'powerbanks': _powerbanksCount,
			};
			final numSeText = _numSeController.text.trim();
			if (numSeText.isNotEmpty) {
				payload['num_se'] = numSeText;
			}
			final resumenCategoria = _resumenCategoriaController.text.trim();
			if (_updateResumen && resumenCategoria.isNotEmpty) {
				payload['resumen_categoria'] = resumenCategoria;
			}
			final referenciaEnvio = _referenciaEnvioController.text.trim();
			if (referenciaEnvio.isNotEmpty) {
				payload['referencia_envio'] = referenciaEnvio;
			}
			final observaciones = _observacionesController.text.trim();
			if (observaciones.isNotEmpty) {
				payload['observaciones'] = observaciones;
			}
			final result = await IgualdadApi.importarRegistroEntrada(
				payload,
				csvBytes: _csvBytes,
				fileName: _pickedFileName ?? 'entrada.csv',
			);
			if (!mounted) return;
			setState(() {
				_importResult = result;
				_submitAttempted = false;
			});
			final processed = result['rows_procesados'] ?? result['rowsProcesados'];
			final processedText = processed != null ? ' ($processed procesados)' : '';
			ScaffoldMessenger.of(context).showSnackBar(
				SnackBar(content: Text('Entrada importada$processedText')),
			);
		} catch (e) {
			if (!mounted) return;
			final message = e.toString().replaceFirst('Exception: ', '');
			ScaffoldMessenger.of(context).showSnackBar(
				SnackBar(content: Text('Error al importar: $message')),
			);
		} finally {
			if (mounted) {
				setState(() => _submitting = false);
			}
		}
	}

	Widget _buildSubmitButton(ThemeData theme) {
		return SizedBox(
			width: double.infinity,
			height: 52,
			child: FilledButton.icon(
				onPressed: (_selectedSource != null && _pickedFileName != null && _numeroPedido.isNotEmpty && _csvBytes != null && !_submitting)
					? _submitBatch
					: null,
				icon: _submitting
					? SizedBox(
						width: 20,
						height: 20,
						child: CircularProgressIndicator(
							strokeWidth: 2.4,
							valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.onPrimary),
						),
					)
					: const Icon(Icons.cloud_upload_outlined),
				label: Text(_submitting ? 'Procesando…' : 'Enviar lote'),
			),
		);
	}

	String _basename(String path) {
		final segments = path.split(RegExp(r'[\\/]'));
		return segments.isNotEmpty ? segments.last : path;
	}

	String? _guessNumeroPedido(String name) {
		final base = _basename(name);
		final upper = base.toUpperCase();
		final seMatch = RegExp(r'SE\d{3,}').firstMatch(upper);
		if (seMatch != null) return seMatch.group(0);
		final digitsMatch = RegExp(r'\d{5,}').firstMatch(base);
		if (digitsMatch != null) return digitsMatch.group(0);
		return null;
	}

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);
		final media = MediaQuery.of(context);
		final isTablet = media.size.shortestSide >= 600;

		return Focus(
			focusNode: _focusRoot,
			child: Scaffold(
				backgroundColor: theme.scaffoldBackgroundColor,
				body: Stack(
					children: [
						Positioned.fill(
							child: SingleChildScrollView(
								padding: EdgeInsets.symmetric(
									horizontal: isTablet ? 48 : 24,
									vertical: isTablet ? 48 : 32,
								),
								child: Center(
									child: ConstrainedBox(
										constraints: const BoxConstraints(maxWidth: 720),
										child: Column(
											crossAxisAlignment: CrossAxisAlignment.start,
											children: [
												Text(
													'Entrada de Stock',
													style: theme.textTheme.headlineMedium?.copyWith(
														fontWeight: FontWeight.bold,
													),
												),
												const SizedBox(height: 8),
												Text(
													'Selecciona el origen y arrastra tu archivo CSV con la información de stock.',
													style: theme.textTheme.bodyMedium?.copyWith(
														color: theme.colorScheme.onSurface.withOpacity(.7),
													),
												),
												const SizedBox(height: 32),
												Card(
													elevation: 6,
													shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
													child: Padding(
														padding: EdgeInsets.symmetric(
															horizontal: isTablet ? 32 : 24,
															vertical: isTablet ? 36 : 28,
														),
														child: Column(
															crossAxisAlignment: CrossAxisAlignment.start,
															children: [
																Text(
																	'Origen del lote',
																	style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
																),
																const SizedBox(height: 12),
																DropdownButtonFormField<String>(
																	initialValue: _selectedSource,
																	decoration: InputDecoration(
																		labelText: 'Selecciona origen',
																		border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
																	),
																	items: const [
																		DropdownMenuItem(value: 'ICP', child: Text('ICP')),
																		DropdownMenuItem(value: 'OYSTA', child: Text('OYSTA')),
																		DropdownMenuItem(value: 'VODAFONE', child: Text('VODAFONE')),
																	],
																	onChanged: (value) => setState(() => _selectedSource = value),
																),
																const SizedBox(height: 8),
																Text(
																	'Selecciona de donde proviene el SE.',
																	style: theme.textTheme.bodySmall?.copyWith(
																		color: theme.colorScheme.onSurface.withOpacity(.65),
																	),
																),
																const SizedBox(height: 32),
																Text(
																	'Archivo CSV',
																	style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
																),
																const SizedBox(height: 12),
																_CsvDropZone(
																	isActive: _dragActive,
																	fileName: _pickedFileName,
																	onPickRequested: _pickCsv,
																	onDragChange: (active) => setState(() => _dragActive = active),
																	onFileDropped: _handleDrop,
																),
																if (_pickedFileName != null) ...[
																	const SizedBox(height: 20),
																	TextField(
																		controller: _numeroPedidoController,
																		textCapitalization: TextCapitalization.characters,
																		decoration: InputDecoration(
																			labelText: 'Número de orden',
																			hintText: 'Introduce el número de orden',
																			helperText: 'Si detectamos el número en el archivo lo rellenamos automáticamente.',
																			border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
																			errorText: (_submitAttempted && _numeroPedido.isEmpty) ? 'Obligatorio' : null,
																		),
																	),
																	const SizedBox(height: 20),
																	_BuildAdvancedOptions(
																		updateResumen: _updateResumen,
																		onUpdateResumenChanged: (value) => setState(() => _updateResumen = value),
																		numSeController: _numSeController,
																		resumenCategoriaController: _resumenCategoriaController,
																		referenciaEnvioController: _referenciaEnvioController,
																		observacionesController: _observacionesController,
																	),
																	const SizedBox(height: 20),
																	_BatchSummary(
																		fileName: _pickedFileName!,
																		botones: _hasExtras ? _botonesCount : 0,
																		powerbanks: _hasExtras ? _powerbanksCount : 0,
																	),
																	const SizedBox(height: 20),
																	_buildSubmitButton(theme),
																	if (_importResult != null) ...[
																		const SizedBox(height: 20),
																		_ImportResultCard(result: _importResult!),
																	],
																],
															],
														),
													),
												),
											],
										),
									),
								),
							),
						),
						const Positioned(left: 0, top: 0, bottom: 0, child: EdgeNavHandle()),
					],
				),
			),
		);
	}
}

class _CsvDropZone extends StatelessWidget {
	final bool isActive;
	final String? fileName;
	final VoidCallback onPickRequested;
	final ValueChanged<bool> onDragChange;
	final VoidCallback onFileDropped;

	const _CsvDropZone({
		required this.isActive,
		required this.fileName,
		required this.onPickRequested,
		required this.onDragChange,
		required this.onFileDropped,
	});

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);
		final borderColor = isActive
			? theme.colorScheme.primary
			: theme.colorScheme.outline.withOpacity(.6);

		return DragTarget<Object>(
			onWillAcceptWithDetails: (_) {
				onDragChange(true);
				return true;
			},
			onLeave: (_) => onDragChange(false),
			onAcceptWithDetails: (details) {
				onDragChange(false);
				onFileDropped();
			},
			builder: (context, candidateData, rejectedData) {
				return InkWell(
					onTap: onPickRequested,
					borderRadius: BorderRadius.circular(18),
					child: AnimatedContainer(
						duration: const Duration(milliseconds: 180),
						padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
						decoration: BoxDecoration(
							borderRadius: BorderRadius.circular(18),
							border: Border.all(color: borderColor, width: 2),
							  color: isActive
								  ? theme.colorScheme.primary.withOpacity(.06)
								  : theme.colorScheme.surfaceContainerHighest.withOpacity(.24),
						),
						child: Column(
							mainAxisSize: MainAxisSize.min,
							children: [
								Icon(
									Icons.cloud_upload_outlined,
									size: 48,
									color: isActive
											? theme.colorScheme.primary
											: theme.colorScheme.onSurface.withOpacity(.6),
								),
								const SizedBox(height: 16),
								Text(
									isActive
											? 'Suelta el archivo CSV aquí'
											: 'Arrastra y suelta el archivo CSV o tócalo para buscar',
									textAlign: TextAlign.center,
									style: theme.textTheme.bodyLarge?.copyWith(
										fontWeight: FontWeight.w600,
										color: theme.colorScheme.onSurface.withOpacity(.8),
									),
								),
								const SizedBox(height: 12),
								Text(
									fileName ?? 'Extensiones permitidas: .csv',
									textAlign: TextAlign.center,
									style: theme.textTheme.bodyMedium?.copyWith(
										color: theme.colorScheme.onSurface.withOpacity(.6),
									),
								),
							],
						),
					),
				);
			},
		);
	}
}

class _BuildAdvancedOptions extends StatelessWidget {
	final bool updateResumen;
	final ValueChanged<bool> onUpdateResumenChanged;
	final TextEditingController numSeController;
	final TextEditingController resumenCategoriaController;
	final TextEditingController referenciaEnvioController;
	final TextEditingController observacionesController;

	const _BuildAdvancedOptions({
		required this.updateResumen,
		required this.onUpdateResumenChanged,
		required this.numSeController,
		required this.resumenCategoriaController,
		required this.referenciaEnvioController,
		required this.observacionesController,
	});

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);
		return Container(
			padding: const EdgeInsets.all(16),
			decoration: BoxDecoration(
				color: theme.colorScheme.surfaceContainerHighest.withOpacity(.25),
				borderRadius: BorderRadius.circular(16),
				border: Border.all(color: theme.colorScheme.outline.withOpacity(.35)),
			),
			child: Column(
				crossAxisAlignment: CrossAxisAlignment.start,
				children: [
					Text(
						'Opciones avanzadas',
						style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
					),
					const SizedBox(height: 12),
					SwitchListTile.adaptive(
						contentPadding: EdgeInsets.zero,
						title: const Text('Actualizar resumen semanal'),
						subtitle: const Text('Desactiva para omitir ResumenSemanal_igualdad.'),
						value: updateResumen,
						onChanged: onUpdateResumenChanged,
					),
					const SizedBox(height: 12),
					TextField(
						controller: numSeController,
						textCapitalization: TextCapitalization.characters,
						decoration: InputDecoration(
							labelText: 'Número SE (opcional)',
							hintText: 'Si lo dejas vacío se usará el número de orden',
							border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
						),
					),
					const SizedBox(height: 12),
					TextField(
						controller: referenciaEnvioController,
						decoration: InputDecoration(
							labelText: 'Referencia de envío (opcional)',
							hintText: 'Sobrescribe referencia_envio',
							border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
						),
					),
					const SizedBox(height: 12),
					if (updateResumen)
						TextField(
							controller: resumenCategoriaController,
							decoration: InputDecoration(
								labelText: 'Resumen categoría (opcional)',
								hintText: 'Ej: Recibido por Securitas',
								border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
							),
						),
					if (updateResumen) const SizedBox(height: 12),
					TextField(
						controller: observacionesController,
						minLines: 2,
						maxLines: 4,
						decoration: InputDecoration(
							labelText: 'Observaciones (opcional)',
							border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
						),
					),
				],
			),
		);
	}
}

class _BatchSummary extends StatelessWidget {
	final String fileName;
	final int botones;
	final int powerbanks;

	const _BatchSummary({
		required this.fileName,
		required this.botones,
		required this.powerbanks,
	});

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);
		return Container(
			padding: const EdgeInsets.all(16),
			decoration: BoxDecoration(
				color: theme.colorScheme.primary.withOpacity(.05),
				borderRadius: BorderRadius.circular(16),
				border: Border.all(color: theme.colorScheme.primary.withOpacity(.15)),
			),
			child: Column(
				crossAxisAlignment: CrossAxisAlignment.start,
				children: [
					Text(
						'Archivo seleccionado',
						style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
					),
					const SizedBox(height: 8),
					Text(fileName, style: theme.textTheme.bodyMedium),
					const SizedBox(height: 16),
					Row(
						children: [
							Expanded(
								child: _summaryTile(theme, 'Botones', botones),
							),
							const SizedBox(width: 12),
							Expanded(
								child: _summaryTile(theme, 'Powerbanks', powerbanks),
							),
						],
					),
				],
			),
		);
	}

	Widget _summaryTile(ThemeData theme, String label, int value) {
		return Container(
			padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
			decoration: BoxDecoration(
				color: theme.colorScheme.surface.withOpacity(.6),
				borderRadius: BorderRadius.circular(12),
				border: Border.all(color: theme.colorScheme.primary.withOpacity(.1)),
			),
			child: Column(
				mainAxisSize: MainAxisSize.min,
				crossAxisAlignment: CrossAxisAlignment.start,
				children: [
					Text(label, style: theme.textTheme.labelMedium),
					const SizedBox(height: 4),
					Text('$value', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
				],
			),
		);
	}
}

class _ImportResultCard extends StatelessWidget {
	final Map<String, dynamic> result;

	const _ImportResultCard({required this.result});

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);
		final counts = <MapEntry<String, String>>[];
		final rawCounts = result['counts'];
		if (rawCounts is Map) {
			rawCounts.forEach((key, value) {
				counts.add(MapEntry(key.toString(), value.toString()));
			});
		}
		final detalles = <MapEntry<String, String>>[];
		final rawDetalles = result['detalles_dispositivo'];
		if (rawDetalles is Map) {
			rawDetalles.forEach((key, value) {
				detalles.add(MapEntry(key.toString(), value.toString()));
			});
		}
		final origenes = <String>[];
		final rawOrigenes = result['origenes'];
		if (rawOrigenes is List) {
			for (final item in rawOrigenes) {
				origenes.add(item.toString());
			}
		}
		final rowsEncontrados = result['rows_encontrados']?.toString();
		final rowsProcesados = result['rows_procesados']?.toString();
		final numeroPedido = result['numero_pedido']?.toString();
		final stock = result['stock'];
		String? stockNumSe;
		String? stockSource;
		String? stockCreatedAt;
		if (stock is Map) {
			final rawNumSe = stock['num_se'];
			if (rawNumSe != null) stockNumSe = rawNumSe.toString();
			final rawSource = stock['source'];
			if (rawSource != null) stockSource = rawSource.toString();
			final rawCreated = stock['created_at'];
			if (rawCreated != null) stockCreatedAt = rawCreated.toString();
		}
		return Container(
			padding: const EdgeInsets.all(16),
			decoration: BoxDecoration(
				color: theme.colorScheme.surfaceContainerHighest.withOpacity(.35),
				borderRadius: BorderRadius.circular(16),
				border: Border.all(color: theme.colorScheme.primary.withOpacity(.12)),
			),
			child: Column(
				crossAxisAlignment: CrossAxisAlignment.start,
				children: [
					Text(
						'Resultado del backend',
						style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
					),
					const SizedBox(height: 12),
					if (numeroPedido != null && numeroPedido.isNotEmpty)
						Text('Número de orden: $numeroPedido', style: theme.textTheme.bodyMedium),
					if (stockNumSe != null)
						Text('Num SE: $stockNumSe', style: theme.textTheme.bodyMedium),
					if (stockSource != null)
						Text('Source: $stockSource', style: theme.textTheme.bodyMedium),
					if (stockCreatedAt != null)
						Text('Creado: $stockCreatedAt', style: theme.textTheme.bodyMedium),
					if (rowsProcesados != null)
						Text('Procesados: $rowsProcesados', style: theme.textTheme.bodyMedium),
					if (rowsEncontrados != null)
						Text('Encontrados: $rowsEncontrados', style: theme.textTheme.bodyMedium),
					if (origenes.isNotEmpty) ...[
						const SizedBox(height: 12),
						Text('Orígenes detectados', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
						Wrap(
							spacing: 8,
							runSpacing: 8,
							children: origenes.map((o) => Chip(label: Text(o))).toList(),
						),
					],
					if (counts.isNotEmpty) ...[
						const SizedBox(height: 16),
						Text('Conteos', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
						Wrap(
							spacing: 8,
							runSpacing: 8,
							children: counts.map((entry) => _metricChip(theme, entry.key, entry.value)).toList(),
						),
					],
					if (detalles.isNotEmpty) ...[
						const SizedBox(height: 16),
						Text('Detalles', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
						Wrap(
							spacing: 8,
							runSpacing: 8,
							children: detalles.map((entry) => _metricChip(theme, entry.key, entry.value)).toList(),
						),
					],
				],
			),
		);
	}

	Widget _metricChip(ThemeData theme, String label, String value) {
		return Chip(
			label: Text('$label: $value'),
			backgroundColor: theme.colorScheme.surface.withOpacity(.6),
		);
	}
}
