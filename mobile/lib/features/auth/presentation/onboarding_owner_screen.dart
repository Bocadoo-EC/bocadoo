import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/external_links.dart';
import '../../../core/utils/formatters.dart';
import '../data/auth_repository.dart';

class OnboardingOwnerScreen extends ConsumerStatefulWidget {
  // D4: precio ingresado en A5 (default $3.50)
  final double precioBase;

  const OnboardingOwnerScreen({super.key, required this.precioBase});

  @override
  ConsumerState<OnboardingOwnerScreen> createState() =>
      _OnboardingOwnerScreenState();
}

class _OnboardingOwnerScreenState extends ConsumerState<OnboardingOwnerScreen> {
  int _step = 1;
  int _puestos = 28;
  bool _anotarMesa = false;
  bool _saving = false;

  // D5: enlace mock con TODO para backend
  static const _inviteLink = 'https://bocadoo.ec/app/unirse?rol=caja&rest=demo';
  // TODO: Conectar con provider de backend para obtener enlace real

  double get _precio => widget.precioBase;

  // D4: cálculo dinámico usando los factores de descuento del MVP (2.80/3.00, 2.75/3.00)
  double _total(int almuerzos) {
    final factor = switch (almuerzos) {
      5 => 1.0,
      10 => 2.80 / 3.00,
      20 => 2.75 / 3.00,
      _ => 1.0,
    };
    return _precio * factor * almuerzos;
  }

  double _precioAlmuerzo(int almuerzos) {
    final factor = switch (almuerzos) {
      5 => 1.0,
      10 => 2.80 / 3.00,
      20 => 2.75 / 3.00,
      _ => 1.0,
    };
    return _precio * factor;
  }

  String _fmt(double v) {
    final rounded = (v * 100).round() / 100;
    return '\$${rounded.toStringAsFixed(2)}';
  }

  Future<void> _savePlansAndContinue() async {
    setState(() => _saving = true);
    try {
      await ref.read(authRepositoryProvider).saveSuggestedPlans([
        SuggestedPlanInput(
          tipo: 'SEMANAL',
          nombre: 'Plan Semanal',
          almuerzos: 5,
          precioCentavos: Money.toCents(_total(5)),
          vigenciaDias: 7,
        ),
        SuggestedPlanInput(
          tipo: 'QUINCENAL',
          nombre: 'Plan Quincenal',
          almuerzos: 10,
          precioCentavos: Money.toCents(_total(10)),
          vigenciaDias: 15,
        ),
        SuggestedPlanInput(
          tipo: 'MENSUAL',
          nombre: 'Plan Mensual',
          almuerzos: 20,
          precioCentavos: Money.toCents(_total(20)),
          vigenciaDias: 30,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _step = 2;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.userMessage)),
      );
    }
  }

  Future<void> _saveCapacityAndContinue() async {
    setState(() => _saving = true);
    try {
      await ref.read(authRepositoryProvider).updateOnboardingCapacity(
            seats: _puestos,
            askTableOnCheckout: _anotarMesa,
          );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _step = 3;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.userMessage)),
      );
    }
  }

  Future<void> _finishOnboarding() async {
    setState(() => _saving = true);
    bool activated = false;
    try {
      activated =
          await ref.read(authRepositoryProvider).completeOwnerOnboarding();
    } on ApiException {
      activated = false;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (!activated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tu local quedó en borrador. Completa tu menú para publicarlo.',
          ),
        ),
      );
    }
    context.go('/owner/caja');
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                _StepChip(
                  label: '1. PLANES SUGERIDOS',
                  active: _step == 1,
                  done: _step > 1,
                ),
                const SizedBox(width: 6),
                _StepChip(
                  label: '2. PUESTOS Y MESAS',
                  active: _step == 2,
                  done: _step > 2,
                ),
                const SizedBox(width: 6),
                _StepChip(
                  label: '3. AYUDANTE',
                  active: _step == 3,
                  done: false,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go('/owner/caja'),
                  child: Text(
                    'Saltar todo',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: switch (_step) {
                  1 => _buildPaso1(context, cs),
                  2 => _buildPaso2(context, cs),
                  _ => _buildPaso3(context, cs),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaso1(BuildContext context, ColorScheme cs) {
    final ahorraSemanal = _total(5);
    final ahorraQuincenal = ahorraSemanal * 2 - _total(10);
    final ahorraMensual = ahorraSemanal * 4 - _total(20);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Planes listos para publicar',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.onSurface),
        ),
        const SizedBox(height: 8),
        Text(
          'Preconfiguramos los 3 planes más vendidos en oficinas y universidades de Quito:',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        _PlanCard(
          tag: 'SEMANAL',
          almuerzos: 5,
          total: _total(5),
          precioAlmuerzo: _precioAlmuerzo(5),
          vigencia: 'Vigencia 7 días',
          highlighted: false,
        ),
        const SizedBox(height: 12),
        _PlanCard(
          tag: 'QUINCENAL',
          almuerzos: 10,
          total: _total(10),
          precioAlmuerzo: _precioAlmuerzo(10),
          ahorra: 'Ahorra ${_fmt(ahorraQuincenal)}',
          highlighted: false,
        ),
        const SizedBox(height: 12),
        _PlanCard(
          tag: 'MENSUAL',
          tagSuffix: 'RECOMENDADO',
          almuerzos: 20,
          total: _total(20),
          precioAlmuerzo: _precioAlmuerzo(20),
          ahorra: 'Ahorra ${_fmt(ahorraMensual)} al mes',
          highlighted: true,
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _saving ? null : _savePlansAndContinue,
          icon: _saving
              ? SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.onPrimary,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 20),
          label: const Text('Usar estos planes'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _step = 2),
          child: Text(
            'Los editaré después',
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _buildPaso2(BuildContext context, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Puestos de tu comedor',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.onSurface),
        ),
        const SizedBox(height: 8),
        Text(
          'Configura el aforo para que Bocadoo te ayude a optimizar rotación en hora pico:',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(children: [
            Text(
              'CAPACIDAD DE COMENSALES SENTADOS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _CounterBtn(
                icon: Icons.remove_rounded,
                enabled: _puestos > 4,
                onPressed: () => setState(() => _puestos -= 2),
              ),
              const SizedBox(width: 32),
              Column(children: [
                Text(
                  '$_puestos',
                  style: TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: cs.primary),
                ),
                Text(
                  'puestos / sillas',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ]),
              const SizedBox(width: 32),
              _CounterBtn(
                icon: Icons.add_rounded,
                enabled: true,
                onPressed: () => setState(() => _puestos += 2),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(AppTheme.inputRadius),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '¿Anotar número de mesa al cobrar?',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  'Apagado por defecto para atender más rápido',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ]),
            ),
            Switch(
              value: _anotarMesa,
              onChanged: (v) => setState(() => _anotarMesa = v),
              activeThumbColor: cs.onPrimary,
              activeTrackColor: cs.primary,
            ),
          ]),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _saving ? null : _saveCapacityAndContinue,
          child: _saving
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.onPrimary,
                  ),
                )
              : const Text('Continuar a invitar ayudante'),
        ),
      ],
    );
  }

  Widget _buildPaso3(BuildContext context, ColorScheme cs) {
    final bColors = context.bocadooColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Invitar ayudante con rol CAJA',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.onSurface),
        ),
        const SizedBox(height: 8),
        Text(
          'Tu ayudante podrá validar almuerzos y registrar ventas desde su propio teléfono sin ver tus ganancias ni reportes privados.',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(AppTheme.inputRadius),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'ENLACE DE INVITACIÓN SEGURO',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _inviteLink,
              style: TextStyle(fontSize: 13, color: cs.primary, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        // Botón verde WhatsApp
        ElevatedButton.icon(
          onPressed: () => openExternal(
            context,
            whatsAppUri('Te invito a la caja de mi local en Bocadoo: $_inviteLink'),
            failMessage: 'No se pudo abrir WhatsApp. Copia el enlace y envíalo a tu ayudante.',
          ),
          icon: const Icon(Icons.send_rounded, size: 20),
          label: const Text('Enviar Invitación por WhatsApp'),
          style: ElevatedButton.styleFrom(
            backgroundColor: bColors.success,
            foregroundColor: bColors.successForeground,
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _saving ? null : _finishOnboarding,
          child: _saving
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.onPrimary,
                  ),
                )
              : const Text('¡Listo, abrir terminal de restaurante!'),
        ),
      ],
    );
  }
}

class _StepChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool done;

  const _StepChip({required this.label, required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: active ? cs.primary : (done ? cs.primaryContainer : cs.secondaryContainer),
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        ),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: active ? cs.onPrimary : (done ? cs.onPrimaryContainer : cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _CounterBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  const _CounterBtn({required this.icon, required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: enabled ? cs.primary : cs.secondaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 28, color: enabled ? cs.onPrimary : cs.onSurfaceVariant),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String tag;
  final String? tagSuffix;
  final int almuerzos;
  final double total;
  final double precioAlmuerzo;
  final String? vigencia;
  final String? ahorra;
  final bool highlighted;

  const _PlanCard({
    required this.tag,
    this.tagSuffix,
    required this.almuerzos,
    required this.total,
    required this.precioAlmuerzo,
    this.vigencia,
    this.ahorra,
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final totalStr = '\$${((total * 100).round() / 100).toStringAsFixed(2)}';
    final paStr = '\$${((precioAlmuerzo * 100).round() / 100).toStringAsFixed(2)}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlighted ? cs.primaryContainer : cs.surface,
        borderRadius: BorderRadius.circular(AppTheme.inputRadius),
        border: Border.all(
          color: highlighted ? cs.primary : cs.outlineVariant,
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: highlighted ? cs.primary : cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: highlighted ? cs.onPrimary : cs.onSecondaryContainer,
                  ),
                ),
              ),
              if (tagSuffix != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                  ),
                  child: Text(
                    tagSuffix!,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onPrimary),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            Text(
              '$almuerzos almuerzos',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
            ),
            const SizedBox(height: 2),
            Text(
              '$paStr por almuerzo'
              '${vigencia != null ? ' · $vigencia' : ''}'
              '${ahorra != null ? ' · $ahorra' : ''}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ]),
        ),
        Text(
          totalStr,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: highlighted ? cs.primary : cs.onSurface,
          ),
        ),
      ]),
    );
  }
}
