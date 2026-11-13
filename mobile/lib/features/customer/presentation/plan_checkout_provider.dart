import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/contracts/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';
import '../data/repositories/customer_plan_repository.dart';
import '../data/repositories/remote_customer_repository.dart';
import '../domain/models/plan_option.dart';
import '../domain/repositories/i_plan_repository.dart';
import 'customer_controller.dart';

/// Provider de Riverpod para el repositorio de paquetes del Comensal
/// (conmuta entre local y remoto según [useRemoteApiProvider]).
final planRepositoryProvider = Provider<IPlanRepository>((ref) {
  final useRemote = ref.watch(useRemoteApiProvider);
  if (useRemote) {
    return RemoteCustomerRepository(dio: ref.watch(dioProvider));
  }
  return CustomerPlanRepository();
});

/// Opciones de paquetes disponibles (5, 10 y 20 almuerzos).
final planOptionsProvider =
    FutureProvider.autoDispose.family<List<PlanOption>, String?>(
  (ref, restaurantId) {
    return ref
        .read(planRepositoryProvider)
        .getPlanOptions(restaurantId: restaurantId);
  },
);

/// Notifier con estado [AsyncValue] para la adquisición o renovación de planes.
final planCheckoutProvider =
    NotifierProvider<PlanCheckoutNotifier, AsyncValue<CustomerPass?>>(
  PlanCheckoutNotifier.new,
);

class PlanCheckoutNotifier extends Notifier<AsyncValue<CustomerPass?>> {
  @override
  AsyncValue<CustomerPass?> build() => const AsyncData(null);

  /// Confirma la selección de un paquete, actualiza el pase activo y retorna el
  /// [CustomerPass] resultante.
  Future<CustomerPass?> confirmPlan({
    required PlanOption option,
    required String restaurantId,
    required String restaurantName,
  }) async {
    state = const AsyncLoading();
    final customerController = ref.read(customerControllerProvider);
    final currentPass = customerController.pass;

    final result = await AsyncValue.guard(() async {
      final updatedPass = await ref.read(planRepositoryProvider).acquirePlan(
            option: option,
            restaurantId: restaurantId,
            restaurantName: restaurantName,
            currentPass: currentPass,
          );
      customerController.updateActivePass(updatedPass);
      return updatedPass;
    });

    state = result;
    return result.value;
  }

  /// Restablece el estado del checkout al cerrar el modal.
  void reset() {
    state = const AsyncData(null);
  }
}

