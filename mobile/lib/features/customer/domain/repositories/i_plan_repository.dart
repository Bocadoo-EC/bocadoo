import '../../../../core/contracts/models.dart';
import '../models/plan_option.dart';

/// Motivo de reclamo permitido sobre un registro del historial.
enum HistoryClaimType {
  notMe('No fui yo'),
  refund('Devolver');

  final String label;
  const HistoryClaimType(this.label);
}

/// Contrato de dominio para adquirir/renovar planes y enviar reclamos del historial.
abstract class IPlanRepository {
  /// Obtiene los paquetes de almuerzos disponibles (5, 10 o 20).
  Future<List<PlanOption>> getPlanOptions({String? restaurantId});

  /// Adquiere o renueva un paquete y devuelve el [CustomerPass] actualizado.
  Future<CustomerPass> acquirePlan({
    required PlanOption option,
    required String restaurantId,
    required String restaurantName,
    CustomerPass? currentPass,
  });

  /// Registra un reclamo sobre un consumo del historial ("No fui yo" / "Devolver").
  Future<void> submitHistoryClaim({
    required String recordId,
    required HistoryClaimType claimType,
  });
}

