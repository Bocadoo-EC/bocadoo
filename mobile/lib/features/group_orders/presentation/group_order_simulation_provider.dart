import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/contracts/models.dart';
import '../../owner/domain/models/extras_models.dart';
import 'group_order_models.dart';

/// Sesión compartida de Pedido Grupal usada para sincronizar Comensal ↔ Invitado ↔ Dueño.
@immutable
class GroupOrderSession {
  final String tableId;
  final String shortCode;
  final String restaurantId;
  final String restaurantName;
  final String hostName;
  final int totalParticipants;
  final DateTime estimatedConsumptionTime;
  final String timeHhmm;
  final TableMode mode;
  final GroupOrderStatus status;
  final DailyMenu dailyMenu;
  final List<GroupOrderParticipant> participants;
  final String qrPayload;
  final String shareUrl;
  final bool sentEarly;

  const GroupOrderSession({
    required this.tableId,
    required this.shortCode,
    required this.restaurantId,
    required this.restaurantName,
    required this.hostName,
    required this.totalParticipants,
    required this.estimatedConsumptionTime,
    required this.timeHhmm,
    required this.mode,
    required this.status,
    required this.dailyMenu,
    required this.participants,
    required this.qrPayload,
    required this.shareUrl,
    this.sentEarly = false,
  });

  int get confirmedCount => participants.length.clamp(1, totalParticipants);

  /// Regla estricta de congelamiento: cuando está confirmado, no admite mutaciones.
  bool get isOrderFrozen => status == GroupOrderStatus.confirmed;

  bool get isReadyForOwner => status == GroupOrderStatus.confirmed;

  GroupOrderSession copyWith({
    GroupOrderStatus? status,
    List<GroupOrderParticipant>? participants,
    int? totalParticipants,
    DateTime? estimatedConsumptionTime,
    String? timeHhmm,
    TableMode? mode,
    bool? sentEarly,
  }) {
    return GroupOrderSession(
      tableId: tableId,
      shortCode: shortCode,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      hostName: hostName,
      totalParticipants: totalParticipants ?? this.totalParticipants,
      estimatedConsumptionTime:
          estimatedConsumptionTime ?? this.estimatedConsumptionTime,
      timeHhmm: timeHhmm ?? this.timeHhmm,
      mode: mode ?? this.mode,
      status: status ?? this.status,
      dailyMenu: dailyMenu,
      participants: participants ?? this.participants,
      qrPayload: qrPayload,
      shareUrl: shareUrl,
      sentEarly: sentEarly ?? this.sentEarly,
    );
  }
}

/// Almacén reactivo en memoria que conecta Anfitrión, Vista Invitado y Pedidos en camino del Dueño.
class GroupOrderSimulationStore extends ChangeNotifier {
  GroupOrderSimulationStore._();

  static final GroupOrderSimulationStore instance = GroupOrderSimulationStore._();

  final Map<String, GroupOrderSession> _sessionsById = {};
  String? _activeSessionId;

  GroupOrderSession? get activeSession =>
      _activeSessionId == null ? null : _sessionsById[_activeSessionId];

  GroupOrderSession? sessionById(String tableId) =>
      _sessionsById[tableId] ??
      _sessionsById.values
          .where((s) => s.shortCode == tableId.toUpperCase())
          .firstOrNull;

  /// Pedidos grupales activos (recolectando o confirmados) para "Pedidos en camino" del Dueño.
  List<PendingTable> get confirmedOwnerTables => ownerTablesFor('');

  List<PendingTable> ownerTablesFor(String restaurantId) {
    final out = <PendingTable>[];
    for (final s in _sessionsById.values) {
      final activeStatus = s.status == GroupOrderStatus.collecting ||
          s.status == GroupOrderStatus.confirmed;
      if (!activeStatus) continue;
      if (restaurantId.isNotEmpty &&
          s.restaurantId.isNotEmpty &&
          s.restaurantId != restaurantId) {
        continue;
      }
      final takeawayCount =
          s.participants.where((p) => p.selection.takeaway).length;
      final planCount = s.participants.where((p) => p.paidByPlan).length;
      final isCollecting = s.status == GroupOrderStatus.collecting;
      final memberCount =
          isCollecting ? s.totalParticipants : s.participants.length;
      final cashCount = (memberCount - planCount).clamp(0, memberCount);
      final surchargeCents = (s.dailyMenu.takeawaySurcharge * 100).round();

      out.add(
        PendingTable(
          id: s.tableId,
          hostName: 'Mesa de ${s.hostName}',
          members: memberCount,
          time: s.timeHhmm,
          planCount: planCount,
          cashCount: cashCount,
          takeawayCount: takeawayCount,
          takeawaySurchargeCents: surchargeCents,
          isCollecting: isCollecting,
          confirmedCount: s.participants.length,
          memberDishes: [
            for (final p in s.participants)
              PendingTableMemberDish(
                memberName: p.name,
                soup: p.selection.cleanSoup,
                main: [
                  if ((p.selection.main ?? '').isNotEmpty) p.selection.main!,
                  ?p.selection.cleanDrink,
                  if ((p.selection.dessert ?? '').isNotEmpty)
                    p.selection.dessert!,
                ].join(' · '),
                extras: p.selection.extras,
                takeaway: p.selection.takeaway,
                hasPlan: p.paidByPlan,
              ),
          ],
        ),
      );
    }
    return out;
  }

  GroupOrderSession startCollecting({
    required String tableId,
    required String shortCode,
    required String restaurantId,
    required String restaurantName,
    required String hostName,
    required int totalParticipants,
    required DateTime estimatedConsumptionTime,
    required String timeHhmm,
    required TableMode mode,
    required DailyMenu dailyMenu,
    required GroupOrderDishSelection hostSelection,
    required String qrPayload,
  }) {
    final host = GroupOrderParticipant(
      id: 'host',
      name: hostName.trim().isNotEmpty ? hostName.trim() : 'Anfitrión',
      isHost: true,
      selection: hostSelection,
      paidByPlan: true,
    );

    final session = GroupOrderSession(
      tableId: tableId,
      shortCode: shortCode.toUpperCase(),
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      hostName: host.name,
      totalParticipants: totalParticipants,
      estimatedConsumptionTime: estimatedConsumptionTime,
      timeHhmm: timeHhmm,
      mode: mode,
      status: GroupOrderStatus.collecting,
      dailyMenu: dailyMenu,
      participants: [host],
      qrPayload: qrPayload,
      shareUrl: buildGroupInviteLink(shortCode),
    );
    _sessionsById[tableId] = session;
    _activeSessionId = tableId;
    notifyListeners();
    return session;
  }

  /// Cambia la elección de un participante mientras la orden NO esté congelada.
  GroupOrderSession? updateDish({
    required String tableId,
    required String participantId,
    required GroupOrderDishSelection selection,
  }) {
    final current = sessionById(tableId);
    if (current == null ||
        current.isOrderFrozen ||
        current.status != GroupOrderStatus.collecting) {
      return null;
    }
    final updatedParticipants = [
      for (final p in current.participants)
        if (p.id == participantId)
          GroupOrderParticipant(
            id: p.id,
            name: p.name,
            isHost: p.isHost,
            selection: selection,
            paidByPlan: p.paidByPlan,
          )
        else
          p,
    ];
    final updated = current.copyWith(participants: updatedParticipants);
    _sessionsById[current.tableId] = updated;
    notifyListeners();
    return updated;
  }

  /// Actualiza configuración de mesa en Fase A (`collecting`), rechazado si `isOrderFrozen`.
  GroupOrderSession? updateTableConfig({
    required String tableId,
    int? totalParticipants,
    DateTime? estimatedConsumptionTime,
    String? timeHhmm,
    TableMode? mode,
  }) {
    final current = sessionById(tableId);
    if (current == null ||
        current.isOrderFrozen ||
        current.status != GroupOrderStatus.collecting) {
      return null;
    }
    final nextTotal = totalParticipants ?? current.totalParticipants;
    if (nextTotal < current.participants.length) {
      return null;
    }
    final nextTime = estimatedConsumptionTime ?? current.estimatedConsumptionTime;
    final nextMode = mode ?? current.mode;
    final updatedParticipants = [
      for (final p in current.participants)
        GroupOrderParticipant(
          id: p.id,
          name: p.name,
          isHost: p.isHost,
          selection: p.selection,
          paidByPlan: p.isHost ? true : (nextMode == TableMode.hostPays),
        ),
    ];

    final shouldFreeze = nextTotal <= updatedParticipants.length &&
        DateTime.now().isBefore(nextTime);

    final updated = current.copyWith(
      totalParticipants: nextTotal,
      estimatedConsumptionTime: nextTime,
      timeHhmm: timeHhmm ?? current.timeHhmm,
      mode: nextMode,
      participants: updatedParticipants,
      status: shouldFreeze ? GroupOrderStatus.confirmed : current.status,
    );
    _sessionsById[current.tableId] = updated;
    notifyListeners();
    return updated;
  }

  /// Cambia modalidad de pago mientras la orden NO esté congelada.
  GroupOrderSession? updatePaymentMode({
    required String tableId,
    required TableMode mode,
  }) =>
      updateTableConfig(tableId: tableId, mode: mode);

  /// Une a un invitado en la simulación y dispara transición a `confirmed` si completa N/N.
  GroupOrderSession? confirmGuestJoin({
    required String tableId,
    required String guestName,
    required GroupOrderDishSelection selection,
  }) {
    final current = sessionById(tableId);
    if (current == null) return null;
    if (current.isOrderFrozen ||
        current.status == GroupOrderStatus.expired ||
        current.status == GroupOrderStatus.cancelled) {
      return current;
    }

    final guest = GroupOrderParticipant(
      id: 'guest-${current.participants.length + 1}',
      name: guestName.trim().isNotEmpty ? guestName.trim() : 'Invitado Prueba',
      isHost: false,
      selection: selection,
      paidByPlan: current.mode == TableMode.hostPays,
    );

    final nextParticipants = [...current.participants, guest];
    final reachedTotal = nextParticipants.length >= current.totalParticipants;
    final stillInTime = DateTime.now().isBefore(current.estimatedConsumptionTime);

    final nextStatus =
        (reachedTotal && stillInTime) ? GroupOrderStatus.confirmed : current.status;

    final updated = current.copyWith(
      participants: nextParticipants,
      status: nextStatus,
    );
    _sessionsById[current.tableId] = updated;
    notifyListeners();
    return updated;
  }

  /// Sincroniza miembros que llegan desde backend (`miembros[].seleccion`, Entrega C).
  /// Respeta estrictamente `m.selection == null` (nunca infiere platos de otros invitados).
  GroupOrderSession? syncRemoteMembers(
    String tableId,
    List<TableMember> remoteMembers,
  ) {
    final current = sessionById(tableId);
    if (current == null || remoteMembers.isEmpty) return current;

    GroupOrderDishSelection mapRemoteSelection(
      TableMember m, {
      GroupOrderDishSelection? fallbackHost,
    }) {
      final sel = m.selection;
      if (sel != null) {
        return GroupOrderDishSelection(
          soup: sel.soup,
          main: sel.main,
          extras: [for (final e in sel.extras) e.formattedLabel],
          takeaway: m.takeaway,
          selectionHidden: false,
        );
      }
      if (m.isHost && fallbackHost != null) {
        return fallbackHost;
      }
      final hasFlatDish = (m.soup?.trim().isNotEmpty ?? false) ||
          (m.main?.trim().isNotEmpty ?? false);
      if (hasFlatDish) {
        return GroupOrderDishSelection(
          soup: m.soup,
          main: m.main,
          takeaway: m.takeaway,
          selectionHidden: false,
        );
      }
      return GroupOrderDishSelection(
        takeaway: m.takeaway,
        selectionHidden: true,
      );
    }

    final existingByKey = <String, GroupOrderParticipant>{
      for (final p in current.participants) p.name.trim().toLowerCase(): p,
    };
    final hostFallback = current.participants.where((p) => p.isHost).firstOrNull?.selection;

    final merged = <GroupOrderParticipant>[];
    for (final m in remoteMembers) {
      final prev = existingByKey[m.name.trim().toLowerCase()];
      final mappedSel = mapRemoteSelection(
        m,
        fallbackHost: m.isHost ? (prev?.selection ?? hostFallback) : null,
      );
      merged.add(
        GroupOrderParticipant(
          id: prev?.id ?? m.id,
          name: m.name,
          isHost: m.isHost,
          selection: mappedSel,
          paidByPlan: m.isHost ? true : (current.mode == TableMode.hostPays),
        ),
      );
    }

    final reachedTotal = merged.length >= current.totalParticipants;
    final stillInTime = DateTime.now().isBefore(current.estimatedConsumptionTime);
    final nextStatus =
        (reachedTotal && stillInTime) ? GroupOrderStatus.confirmed : current.status;

    final updated = current.copyWith(
      participants: merged,
      status: nextStatus,
    );
    _sessionsById[current.tableId] = updated;
    notifyListeners();
    return updated;
  }

  /// Confirmación manual por el anfitrión ("Cerrar mesa y enviar con los que estamos").
  GroupOrderSession? confirmNow(String tableId) {
    final current = sessionById(tableId);
    if (current == null) return null;
    final updated = current.copyWith(
      status: GroupOrderStatus.confirmed,
      sentEarly: true,
    );
    _sessionsById[current.tableId] = updated;
    notifyListeners();
    return updated;
  }

  /// Transición automática a Caducada (libera holds y retira de pendientes).
  GroupOrderSession? markExpired(String tableId) {
    final current = sessionById(tableId);
    if (current == null) return null;
    final updated = current.copyWith(status: GroupOrderStatus.expired);
    _sessionsById[current.tableId] = updated;
    notifyListeners();
    return updated;
  }

  void markCancelled(String tableId) {
    final current = sessionById(tableId);
    if (current == null) return;
    _sessionsById[current.tableId] =
        current.copyWith(status: GroupOrderStatus.cancelled);
    if (_activeSessionId == current.tableId) {
      _activeSessionId = null;
    }
    notifyListeners();
  }

  void clearActive() {
    _activeSessionId = null;
    notifyListeners();
  }
}

/// Provider global del simulador de Pedido Grupal (Comensal ↔ Invitado ↔ Dueño).
final groupOrderSimulationProvider = Provider<GroupOrderSimulationStore>((ref) {
  return GroupOrderSimulationStore.instance;
});
