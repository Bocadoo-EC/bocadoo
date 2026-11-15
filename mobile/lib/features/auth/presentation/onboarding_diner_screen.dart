import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';

class OnboardingDinerScreen extends StatelessWidget {
  final String nombre;
  final String zona;

  const OnboardingDinerScreen({super.key, required this.nombre, required this.zona});

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.auto_awesome_rounded, size: 32, color: cs.primary),
                ),
              ),

              const SizedBox(height: 16),

              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                  ),
                  child: Text(
                    '¡Bienvenido a Bocadoo Ecuador!',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // D3: sin emoji en el titular
              Text(
                '¡Hola, $nombre!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: cs.onSurface),
              ),

              const SizedBox(height: 8),

              Text(
                'Tu cuenta comensal en $zona está lista. Como es tu primera vez, entras sin saldo prepagado. Explora los comedores afiliados en Quito y elige tu primer paquete.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              ),

              const SizedBox(height: 28),

              _Paso(
                numero: 1,
                titulo: 'Elige tu restaurante preferido',
                descripcion: 'Explora restaurantes en $zona y compra tu primer plan de 5, 10 o 20 almuerzos con descuento.',
              ),

              const SizedBox(height: 16),

              _Paso(
                numero: 2,
                titulo: 'Tu código QR personal listo',
                descripcion: 'Al llegar al restaurante, abre tu QR en pantalla completa. El cajero lo escanea en 2 segundos.',
              ),

              const SizedBox(height: 16),

              _Paso(
                numero: 3,
                titulo: 'Control de tus almuerzos',
                descripcion: 'Revisa cuántos almuerzos te quedan en tiempo real y cuándo vence tu plan prepagado.',
              ),

              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                ),
                child: Row(children: [
                  Icon(Icons.qr_code_2_rounded, size: 24, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '¡Tu código QR de bienvenida ya está generado!',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer),
                    ),
                  ),
                ]),
              ),

              const Spacer(),

              // D1: navega a C2 Dónde comer
              ElevatedButton(
                onPressed: () => context.go('/customer/restaurants'),
                child: const Text('Explorar restaurantes en Quito'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  final int numero;
  final String titulo;
  final String descripcion;

  const _Paso({required this.numero, required this.titulo, required this.descripcion});

  @override
  Widget build(BuildContext context) {
    final cs = context.colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
        child: Center(
          child: Text(
            '$numero',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onPrimary),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 4),
          Text(descripcion, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ]),
      ),
    ]);
  }
}
