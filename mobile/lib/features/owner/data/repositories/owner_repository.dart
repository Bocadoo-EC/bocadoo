import '../../../../core/contracts/models.dart';
import '../../../../core/contracts/repositories.dart';
import '../../domain/models/daily_menu.dart';
import '../../domain/repositories/i_owner_repository.dart';
import '../mock_owner_repo.dart';

/// Repositorio concreto del Dueño. Delega operaciones de QR/venta al
/// [MockOwnerRepository] y gestiona el estado del menú diario en memoria.
/// Para pasar al backend real basta con reemplazar [_delegate] por un
/// [ApiOwnerRepository] y conectar [publishMenu] al endpoint correspondiente.
class OwnerRepository implements IOwnerRepository, IOwnerMenuRepository {
  OwnerRepository({MockOwnerRepository? delegate})
      : _delegate = delegate ?? MockOwnerRepository();

  final MockOwnerRepository _delegate;

  DailyMenu? _todayMenu;

  // ── IOwnerRepository (delegado al mock) ────────────────────────────────────

  @override
  Future<ScanResult> validateQrCode(String rawPayload) =>
      _delegate.validateQrCode(rawPayload);

  @override
  Future<bool> confirmRedeem(String passId) =>
      _delegate.confirmRedeem(passId);

  @override
  Future<bool> sellPlan({
    required String studentIdentifier,
    required int lunchCount,
    required String paymentMethod,
    required double amount,
  }) =>
      _delegate.sellPlan(
        studentIdentifier: studentIdentifier,
        lunchCount: lunchCount,
        paymentMethod: paymentMethod,
        amount: amount,
      );

  @override
  Future<TransactionSummary> getDailyClosingSummary(String restaurantId) =>
      _delegate.getDailyClosingSummary(restaurantId);

  @override
  Future<List<TransactionItem>> getTodayTransactions(String restaurantId) =>
      _delegate.getTodayTransactions(restaurantId);

  // ── IOwnerMenuRepository ───────────────────────────────────────────────────

  @override
  Future<DailyMenu?> getTodayMenu(String restaurantId) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _todayMenu;
  }

  @override
  Future<DailyMenu?> getYesterdayMenu(String restaurantId) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _defaultYesterdayMenu(restaurantId);
  }

  @override
  Future<bool> publishMenu(DailyMenu menu) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _todayMenu = menu.copyWith(isPublished: true);
    return true;
  }

  @override
  Future<bool> markSoldOut(String restaurantId) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (_todayMenu == null) return false;
    _todayMenu = _todayMenu!.copyWith(isPublished: false);
    return true;
  }

  @override
  Future<bool> setStoreOpen(String restaurantId, {required bool isOpen}) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (_todayMenu != null) {
      _todayMenu = _todayMenu!.copyWith(isOpen: isOpen);
    }
    return true;
  }

  // ── Semilla de ayer ─────────────────────────────────────────────────────────

  static DailyMenu _defaultYesterdayMenu(String restaurantId) => DailyMenu(
        restaurantId: restaurantId,
        date: DateTime.now().subtract(const Duration(days: 1)),
        courses: const [
          DailyMenuCourse(
              id: 'y1', name: 'Locro de papa', category: 'Sopa'),
          DailyMenuCourse(
              id: 'y2', name: 'Pollo a la plancha', category: 'Fuerte'),
          DailyMenuCourse(
              id: 'y3', name: 'Jugo de naranjilla', category: 'Jugo'),
          DailyMenuCourse(
              id: 'y4', name: 'Higos con queso', category: 'Postre'),
        ],
        isPublished: true,
        isOpen: true,
      );
}
