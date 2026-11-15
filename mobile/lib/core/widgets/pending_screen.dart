import 'package:material_ui/material_ui.dart';

/// Marcador de navegación para pantallas de la migración que aún no tienen diseño ni lógica.
class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          'Pantalla pendiente de migración',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
