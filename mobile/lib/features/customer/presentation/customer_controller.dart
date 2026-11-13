import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/contracts/models.dart';
import '../../../core/contracts/repositories.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';
import '../data/mock_customer_repo.dart';
import '../data/repositories/remote_customer_repository.dart';

/// Estados posibles de la interfaz del Comensal
enum CustomerStatus { initial, loading, success, error }

/// Estado inmutable de la pantalla del Comensal
@immutable
class CustomerUiState {
  final CustomerStatus status;
  final CustomerPass? pass;
  final List<Restaurant> restaurants;
  final List<Restaurant> filteredRestaurants;
  final List<ConsumptionRecord> history;
  final String searchQuery;
  final String selectedCategory;
  final String? errorMessage;
  final bool isRefreshingQr;
  final bool isOffline;
  final Restaurant? selectedRestaurant;
  final List<MenuItem> selectedMenu;

  const CustomerUiState({
    this.status = CustomerStatus.initial,
    this.pass,
    this.restaurants = const [],
    this.filteredRestaurants = const [],
    this.history = const [],
    this.searchQuery = '',
    this.selectedCategory = 'Todos',
    this.errorMessage,
    this.isRefreshingQr = false,
    this.isOffline = false,
    this.selectedRestaurant,
    this.selectedMenu = const [],
  });

  bool get isLoading => status == CustomerStatus.loading;
  bool get isSuccess => status == CustomerStatus.success;
  bool get isError => status == CustomerStatus.error;

  CustomerUiState copyWith({
    CustomerStatus? status,
    CustomerPass? pass,
    List<Restaurant>? restaurants,
    List<Restaurant>? filteredRestaurants,
    List<ConsumptionRecord>? history,
    String? searchQuery,
    String? selectedCategory,
    String? errorMessage,
    bool? isRefreshingQr,
    bool? isOffline,
    Restaurant? selectedRestaurant,
    List<MenuItem>? selectedMenu,
  }) {
    return CustomerUiState(
      status: status ?? this.status,
      pass: pass ?? this.pass,
      restaurants: restaurants ?? this.restaurants,
      filteredRestaurants: filteredRestaurants ?? this.filteredRestaurants,
      history: history ?? this.history,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      errorMessage: errorMessage,
      isRefreshingQr: isRefreshingQr ?? this.isRefreshingQr,
      isOffline: isOffline ?? this.isOffline,
      selectedRestaurant: selectedRestaurant ?? this.selectedRestaurant,
      selectedMenu: selectedMenu ?? this.selectedMenu,
    );
  }
}

/// Gestor de estado para el Comensal (Estudiante)
/// Extiende [ChangeNotifier] para soportar `AnimatedBuilder`, `ListenableBuilder`
/// y Riverpod mediante [customerControllerProvider].
class CustomerController extends ChangeNotifier {
  final ICustomerRepository _repository;
  CustomerUiState _state = const CustomerUiState();

  CustomerController({ICustomerRepository? repository})
      : _repository = repository ?? MockCustomerRepository();

  CustomerUiState get state => _state;
  CustomerPass? get pass => _state.pass;
  List<Restaurant> get restaurants => _state.filteredRestaurants;
  List<ConsumptionRecord> get history => _state.history;
  bool get isLoading => _state.isLoading;
  String? get errorMessage => _state.errorMessage;

  /// Carga inicial o recarga del Dashboard del Comensal
  Future<void> loadDashboard({bool silent = false}) async {
    if (!silent) {
      _state = _state.copyWith(
        status: CustomerStatus.loading,
        errorMessage: null,
      );
      notifyListeners();
    }

    try {
      // Intenta usar pase local de caché primero para respuesta instantánea
      final cached = await _repository.getCachedPass();
      if (cached != null && _state.pass == null) {
        _state = _state.copyWith(pass: cached);
        notifyListeners();
      }

      final activePass = await _repository.getActivePass();
      final allRestaurants = await _repository.getRestaurants();
      final records = await _repository.getConsumptionHistory(activePass.id);

      final filtered = _applyFilters(
        allRestaurants,
        _state.searchQuery,
        _state.selectedCategory,
      );

      _state = _state.copyWith(
        status: CustomerStatus.success,
        pass: activePass,
        restaurants: allRestaurants,
        filteredRestaurants: filtered,
        history: records,
        isOffline: false,
        errorMessage: null,
      );
    } catch (e) {
      // Si falla la red pero hay datos en memoria/caché, no se bloquea la UI
      if (_state.pass != null) {
        _state = _state.copyWith(
          status: CustomerStatus.success,
          isOffline: true,
          errorMessage: 'Modo Offline · Código guardado',
        );
      } else {
        _state = _state.copyWith(
          status: CustomerStatus.error,
          isOffline: false,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      notifyListeners();
    }
  }

  /// Refresca el token del código QR dinámico (anti-captura)
  Future<void> refreshQr() async {
    final currentPass = _state.pass;
    if (currentPass == null) return;

    _state = _state.copyWith(isRefreshingQr: true);
    notifyListeners();

    try {
      final newToken = await _repository.refreshQrToken(currentPass.id);
      final updatedPass = currentPass.copyWith(qrToken: newToken);
      await _repository.saveCachedPass(updatedPass);

      _state = _state.copyWith(
        pass: updatedPass,
        isRefreshingQr: false,
      );
    } catch (_) {
      _state = _state.copyWith(
        isRefreshingQr: false,
        errorMessage: 'No se pudo regenerar el QR en este momento.',
      );
    } finally {
      notifyListeners();
    }
  }

  /// Filtra restaurantes en memoria por texto y/o categoría sin llamadas pesadas
  void filterRestaurants(String query, {String? category}) {
    final cat = category ?? _state.selectedCategory;
    final filtered = _applyFilters(_state.restaurants, query, cat);

    _state = _state.copyWith(
      searchQuery: query,
      selectedCategory: cat,
      filteredRestaurants: filtered,
    );
    notifyListeners();
  }

  /// Cambia la categoría seleccionada en los filtros
  void selectCategory(String category) {
    filterRestaurants(_state.searchQuery, category: category);
  }

  /// Selecciona un restaurante y obtiene su menú del día
  Future<void> selectRestaurant(Restaurant restaurant) async {
    _state = _state.copyWith(
      selectedRestaurant: restaurant,
      selectedMenu: restaurant.todayMenu,
    );
    notifyListeners();

    try {
      final freshMenu = await _repository.getTodayMenu(restaurant.id);
      _state = _state.copyWith(selectedMenu: freshMenu);
      notifyListeners();
    } catch (_) {
      // Conserva el menú ya asociado en caso de error
    }
  }

  /// Actualiza inmediatamente el pase activo tras adquirir o renovar un paquete.
  void updateActivePass(CustomerPass updatedPass) {
    _state = _state.copyWith(
      status: CustomerStatus.success,
      pass: updatedPass,
      errorMessage: null,
    );
    notifyListeners();
  }

  List<Restaurant> _applyFilters(
    List<Restaurant> list,
    String query,
    String category,
  ) {
    return list.where((r) {
      final matchesQuery = query.isEmpty ||
          r.name.toLowerCase().contains(query.toLowerCase()) ||
          r.zone.toLowerCase().contains(query.toLowerCase()) ||
          r.description.toLowerCase().contains(query.toLowerCase());

      final matchesCategory = category.isEmpty ||
          category == 'Todos' ||
          r.categories.contains(category);

      return matchesQuery && matchesCategory;
    }).toList();
  }
}

/// Provider de Riverpod para el repositorio de Comensal (conmuta según [useRemoteApiProvider]).
final customerRepositoryProvider = Provider<ICustomerRepository>((ref) {
  final useRemote = ref.watch(useRemoteApiProvider);
  if (useRemote) {
    return RemoteCustomerRepository(dio: ref.watch(dioProvider));
  }
  return MockCustomerRepository();
});

/// Provider de Riverpod para el controlador de estado del Comensal
final customerControllerProvider = Provider<CustomerController>((ref) {
  final repo = ref.watch(customerRepositoryProvider);
  final controller = CustomerController(repository: repo);
  controller.loadDashboard();
  ref.onDispose(controller.dispose);
  return controller;
});
