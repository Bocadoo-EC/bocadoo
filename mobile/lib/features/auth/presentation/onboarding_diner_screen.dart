import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';

/// Bienvenida interactiva por pasos tras el registro del comensal.
class OnboardingDinerScreen extends StatefulWidget {
  final String nombre;
  final String zona;

  const OnboardingDinerScreen({
    super.key,
    required this.nombre,
    required this.zona,
  });

  @override
  State<OnboardingDinerScreen> createState() => _OnboardingDinerScreenState();
}

class _OnboardingDinerScreenState extends State<OnboardingDinerScreen> {
  static const int _totalSteps = 3;

  late final PageController _pageCtrl = PageController();
  int _step = 0;

  // Estados interactivos locales de demostración (solo UX frontend).
  int _previewPlanLunches = 10;
  bool _previewQrScanned = false;
  int _previewRemaining = 5;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _goToStep(int target) {
    final clamped = target.clamp(0, _totalSteps - 1);
    _pageCtrl.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _finishOnboarding() {
    context.go('/customer/restaurants');
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final bColors = context.bocadooColors;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Barra superior: progreso + omitir
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                    ),
                    child: Text(
                      'Paso ${_step + 1} de $_totalSteps',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_step < _totalSteps - 1)
                    TextButton(
                      onPressed: _finishOnboarding,
                      child: const Text('Saltar'),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: bColors.successContainer,
                        borderRadius: BorderRadius.circular(
                          AppTheme.buttonRadius,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: bColors.success,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Cuenta lista',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: bColors.onSuccessContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Barra segmentada interactiva de pasos
              Row(
                children: List.generate(_totalSteps, (i) {
                  final active = i == _step;
                  final completed = i < _step;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _goToStep(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        height: 6,
                        margin: EdgeInsets.only(right: i < _totalSteps - 1 ? 8 : 0),
                        decoration: BoxDecoration(
                          color: active
                              ? cs.primary
                              : (completed
                                  ? cs.primary.withValues(alpha: 0.45)
                                  : cs.primaryContainer),
                          borderRadius: BorderRadius.circular(
                            AppTheme.buttonRadius,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 20),

              // Cabecera personalizada
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 15,
                        color: cs.onPrimaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '¡Bienvenido a Bocadoo Ecuador!',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // D3: sin emoji en el titular
              Text(
                '¡Hola, ${widget.nombre}!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),

              const SizedBox(height: 6),

              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 14,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Sector ${widget.zona} · Sin saldo inicial',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // Carrusel interactivo paso a paso
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  onPageChanged: (index) => setState(() => _step = index),
                  children: [
                    _StepOneCard(
                      zona: widget.zona,
                      selectedLunches: _previewPlanLunches,
                      onSelectLunches: (val) =>
                          setState(() => _previewPlanLunches = val),
                    ),
                    _StepTwoCard(
                      scanned: _previewQrScanned,
                      onToggleScan: () => setState(
                        () => _previewQrScanned = !_previewQrScanned,
                      ),
                    ),
                    _StepThreeCard(
                      remaining: _previewRemaining,
                      onSimulateConsume: () => setState(() {
                        _previewRemaining =
                            _previewRemaining > 1 ? _previewRemaining - 1 : 5;
                      }),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Indicadores + navegación inferior
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_totalSteps, (i) {
                  final active = i == _step;
                  return GestureDetector(
                    onTap: () => _goToStep(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: active ? 22 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: active ? cs.primary : cs.outlineVariant,
                        borderRadius: BorderRadius.circular(
                          AppTheme.buttonRadius,
                        ),
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 16),

              if (_step < _totalSteps - 1)
                Row(
                  children: [
                    if (_step > 0) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _goToStep(_step - 1),
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Anterior'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: _step > 0 ? 2 : 1,
                      child: ElevatedButton(
                        onPressed: () => _goToStep(_step + 1),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Siguiente'),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: cs.onPrimary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // D1: navega a C2 Dónde comer
                    ElevatedButton(
                      onPressed: _finishOnboarding,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.store_mall_directory_rounded,
                            size: 20,
                            color: cs.onPrimary,
                          ),
                          const SizedBox(width: 8),
                          const Text('Explorar restaurantes en Quito'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => _goToStep(_step - 1),
                      child: const Text('Volver al paso anterior'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingStepShell extends StatelessWidget {
  final int stepNumber;
  final IconData icon;
  final String title;
  final String description;
  final Widget interactivePreview;

  const _OnboardingStepShell({
    required this.stepNumber,
    required this.icon,
    required this.title,
    required this.description,
    required this.interactivePreview,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(icon, size: 34, color: cs.primary),
                          ),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: cs.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: cs.surface,
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '$stepNumber',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: cs.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  interactivePreview,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepOneCard extends StatelessWidget {
  final String zona;
  final int selectedLunches;
  final ValueChanged<int> onSelectLunches;

  const _StepOneCard({
    required this.zona,
    required this.selectedLunches,
    required this.onSelectLunches,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final bColors = context.bocadooColors;
    final benefitText = switch (selectedLunches) {
      5 => 'Ideal para probar una semana completa cerca de $zona.',
      10 => 'El favorito para ahorrar en dos semanas de almuerzos.',
      _ => 'Máximo ahorro mensual para almorzar sin preocupaciones.',
    };

    return _OnboardingStepShell(
      stepNumber: 1,
      icon: Icons.storefront_rounded,
      title: 'Elige tu restaurante preferido',
      description:
          'Explora comedores afiliados en $zona, revisa el menú de hoy y elige un paquete prepagado con descuento.',
      interactivePreview: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Prueba comparar tamaños de plan:',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [5, 10, 20].map((count) {
                final selected = selectedLunches == count;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: count == 20 ? 0 : 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSelectLunches(count),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: selected ? cs.primary : cs.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? cs.primary : cs.outlineVariant,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: selected ? cs.onPrimary : cs.onSurface,
                              ),
                            ),
                            Text(
                              'almuerzos',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? cs.onPrimary.withValues(alpha: 0.9)
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.verified_rounded, size: 15, color: bColors.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    benefitText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTwoCard extends StatelessWidget {
  final bool scanned;
  final VoidCallback onToggleScan;

  const _StepTwoCard({
    required this.scanned,
    required this.onToggleScan,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final bColors = context.bocadooColors;

    return _OnboardingStepShell(
      stepNumber: 2,
      icon: Icons.qr_code_2_rounded,
      title: 'Tu código QR personal listo',
      description:
          'Al llegar al local, muestra tu pase QR desde la pantalla principal. El cajero lo valida en 2 segundos.',
      interactivePreview: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onToggleScan,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scanned
                ? bColors.successContainer
                : cs.primaryContainer.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scanned
                  ? bColors.success.withValues(alpha: 0.45)
                  : cs.primary.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  scanned
                      ? Icons.check_circle_rounded
                      : Icons.qr_code_scanner_rounded,
                  color: scanned ? bColors.success : cs.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scanned
                          ? 'Almuerzo validado en caja'
                          : '¡Tu código QR de bienvenida está listo!',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: scanned
                            ? bColors.onSuccessContainer
                            : cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      scanned
                          ? 'Sin cartulinas ni efectivo · Toca para reiniciar'
                          : 'Toca aquí para simular el escaneo en caja',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: scanned
                            ? bColors.onSuccessContainer.withValues(alpha: 0.85)
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepThreeCard extends StatelessWidget {
  final int remaining;
  final VoidCallback onSimulateConsume;

  const _StepThreeCard({
    required this.remaining,
    required this.onSimulateConsume,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    final bColors = context.bocadooColors;

    return _OnboardingStepShell(
      stepNumber: 3,
      icon: Icons.confirmation_number_rounded,
      title: 'Control de tus almuerzos',
      description:
          'Mira en tiempo real cuántos cupos te quedan, arma tu orden del día antes de llegar y revisa cuándo vence tu plan.',
      interactivePreview: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '$remaining de 5 disponibles',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: bColors.successContainer,
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                  ),
                  child: Text(
                    'Tiempo real',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: bColors.onSuccessContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              child: LinearProgressIndicator(
                value: remaining / 5,
                minHeight: 8,
                backgroundColor: cs.surface,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onSimulateConsume,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: Icon(
                  remaining > 1
                      ? Icons.remove_circle_outline_rounded
                      : Icons.refresh_rounded,
                  size: 16,
                ),
                label: Text(
                  remaining > 1 ? 'Simular uso (-1 cupo)' : 'Reiniciar demo',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
