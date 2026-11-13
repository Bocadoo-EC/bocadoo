import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/widgets.dart';
import 'owner_bottom_nav.dart';

class _DailyDish {
  final String id;
  final String category;
  final String name;
  final bool soldOut;

  const _DailyDish({
    required this.id,
    required this.category,
    required this.name,
    this.soldOut = false,
  });

  _DailyDish copyWith({bool? soldOut}) => _DailyDish(
        id: id,
        category: category,
        name: name,
        soldOut: soldOut ?? this.soldOut,
      );
}

/// Pantalla de Menú del Día para el Dueño ("Repetir ayer", "Se acabó", "Publicar").
class OwnerMenuScreen extends ConsumerStatefulWidget {
  const OwnerMenuScreen({super.key});

  @override
  ConsumerState<OwnerMenuScreen> createState() => _OwnerMenuScreenState();
}

class _OwnerMenuScreenState extends ConsumerState<OwnerMenuScreen> {
  bool _published = true;
  List<_DailyDish> _dishes = const [
    _DailyDish(id: '1', category: 'Sopa', name: 'Locro de papa con queso'),
    _DailyDish(
      id: '2',
      category: 'Plato fuerte',
      name: 'Seco de pollo con arroz y maduro',
    ),
    _DailyDish(
      id: '3',
      category: 'Plato fuerte',
      name: 'Guatita criolla con aguacate',
    ),
    _DailyDish(id: '4', category: 'Jugo', name: 'Jugo de naranjilla'),
  ];

  void _repeatYesterday() {
    setState(() {
      _dishes = const [
        _DailyDish(
          id: '1',
          category: 'Sopa',
          name: 'Crema de zapallo con crutones',
        ),
        _DailyDish(
          id: '2',
          category: 'Plato fuerte',
          name: 'Carne apanada con menestra y ensalada',
        ),
        _DailyDish(
          id: '3',
          category: 'Plato fuerte',
          name: 'Arroz con pollo y salsa criolla',
        ),
        _DailyDish(id: '4', category: 'Jugo', name: 'Limonada con hierbabuena'),
      ];
      _published = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Menú de ayer cargado. Pulsa "Publicar" para mostrarlo.'),
      ),
    );
  }

  void _toggleSoldOut(String id) {
    setState(() {
      _dishes = _dishes
          .map((d) => d.id == id ? d.copyWith(soldOut: !d.soldOut) : d)
          .toList();
    });
  }

  void _addDishModal() {
    final nameController = TextEditingController();
    String category = 'Plato fuerte';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                8,
                24,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Agregar plato al menú',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tipo de plato',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['Sopa', 'Plato fuerte', 'Jugo', 'Postre']
                        .map(
                          (c) => ChoiceChip(
                            label: Text(c),
                            selected: category == c,
                            onSelected: (_) => setSheetState(() => category = c),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del plato',
                      hintText: 'Ej. Menestrón con carne asada',
                    ),
                  ),
                  const SizedBox(height: 20),
                  BocadooButton(
                    label: 'Agregar plato',
                    icon: Icons.add_rounded,
                    onPressed: () {
                      final text = nameController.text.trim();
                      if (text.isEmpty) return;
                      setState(() {
                        _dishes = [
                          ..._dishes,
                          _DailyDish(
                            id: DateTime.now().millisecondsSinceEpoch.toString(),
                            category: category,
                            name: text,
                          ),
                        ];
                        _published = false;
                      });
                      Navigator.of(sheetCtx).pop();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(nameController.dispose);
  }

  void _publishMenu() {
    setState(() => _published = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Menú del día publicado para tus comensales.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bColor = context.bocadooColors;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Menú de hoy'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: _repeatYesterday,
            icon: const Icon(Icons.history_rounded, size: 20),
            label: const Text('Repetir ayer'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _published
                  ? bColor.successContainer
                  : colors.primaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            ),
            child: Row(
              children: [
                Icon(
                  _published
                      ? Icons.check_circle_rounded
                      : Icons.edit_note_rounded,
                  color: _published
                      ? bColor.onSuccessContainer
                      : colors.onPrimaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _published
                        ? 'Tu menú está visible en Dónde comer.'
                        : 'Tienes cambios sin publicar.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _published
                          ? bColor.onSuccessContainer
                          : colors.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: Text(
                  'Platos del día',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _addDishModal,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Agregar'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          for (final dish in _dishes) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dish.category,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dish.name,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            decoration: dish.soldOut
                                ? TextDecoration.lineThrough
                                : null,
                            color: dish.soldOut
                                ? colors.onSurfaceVariant
                                : colors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilterChip(
                    label: Text(dish.soldOut ? 'Se acabó' : 'Disponible'),
                    selected: dish.soldOut,
                    onSelected: (_) => _toggleSoldOut(dish.id),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          const SizedBox(height: 16),
          BocadooButton(
            label: 'Publicar',
            icon: Icons.publish_rounded,
            onPressed: _publishMenu,
          ),
        ],
      ),
      bottomNavigationBar: const OwnerBottomNav(currentRoute: '/owner/menu'),
    );
  }
}

