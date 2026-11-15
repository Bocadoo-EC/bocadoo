import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/models/cash_models.dart';
import 'owner_controller.dart';
import 'owner_widgets.dart';

/// Lo que devuelve la hoja: el cliente guardado y si se quiere venderle un plan ya.
typedef AddedClient = ({OwnerClient client, bool sellPlan});

final _phonePattern = RegExp(r'^09\d{8}$');
final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// O8 · Agregar cliente: datos básicos para tenerlo en la lista y venderle un
/// plan de inmediato. Nombre y teléfono son obligatorios.
class AddClientSheet extends ConsumerStatefulWidget {
  const AddClientSheet({super.key});

  @override
  ConsumerState<AddClientSheet> createState() => _AddClientSheetState();
}

class _AddClientSheetState extends ConsumerState<AddClientSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  bool _submitted = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? get _nameError => _submitted && _name.text.trim().isEmpty ? 'Escribe el nombre del cliente.' : null;

  String? get _phoneError {
    final p = _phone.text.trim();
    if (p.isEmpty) return _submitted ? 'Escribe su celular.' : null;
    if (p.length == 10 && !_phonePattern.hasMatch(p)) return 'Debe empezar con 09.';
    return _submitted && !_phonePattern.hasMatch(p) ? 'Celular de 10 dígitos (09XXXXXXXX).' : null;
  }

  String? get _emailError {
    final e = _email.text.trim();
    return e.isNotEmpty && !_emailPattern.hasMatch(e) ? 'Revisa el correo.' : null;
  }

  Future<void> _save({required bool sellPlan}) async {
    setState(() => _submitted = true);
    if (_nameError != null || _phoneError != null || _emailError != null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final client = await ref.read(ownerCashRepositoryProvider).addClient(
            ref.read(ownerRestaurantIdProvider),
            name: _name.text,
            phone: _phone.text,
            email: _email.text,
            notes: _notes.text,
          );
      if (!mounted) return;
      navigator.pop<AddedClient>((client: client, sellPlan: sellPlan));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showInfoSnackBar(messenger, 'No se pudo guardar el cliente. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Agregar cliente',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.onSurface)),
                Text('Regístralo y véndele un plan al instante',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant)),
              ]),
            ),
            IconButton.filledTonal(
              tooltip: 'Cerrar',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Nombre del cliente',
              prefixIcon: const Icon(Icons.person_outline_rounded),
              errorText: _nameError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Celular',
              hintText: '09XXXXXXXX',
              prefixIcon: const Icon(Icons.phone_outlined),
              errorText: _phoneError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Correo (opcional)',
              prefixIcon: const Icon(Icons.mail_outline_rounded),
              errorText: _emailError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notas (opcional)',
              hintText: 'Ej. Prefiere sin picante',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _saving ? null : () => _save(sellPlan: false),
            icon: _saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary),
                  )
                : const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Guardar cliente'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: _saving ? null : () => _save(sellPlan: true),
            icon: const Icon(Icons.group_outlined),
            label: const Text('Guardar y vender plan'),
          ),
        ]),
      ),
    );
  }
}
