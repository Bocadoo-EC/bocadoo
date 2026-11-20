part of 'group_order_flow_screen.dart';

class _StepProgressHeader extends StatelessWidget {
  const _StepProgressHeader({
    required this.restaurantName,
    required this.stepNumber,
    required this.isExpired,
    this.showOverflowMenu = false,
    this.onOpenGuestView,
    this.onCancelTable,
  });

  final String restaurantName;
  final int stepNumber;
  final bool isExpired;
  final bool showOverflowMenu;
  final VoidCallback? onOpenGuestView;
  final VoidCallback? onCancelTable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final progress = isExpired ? 1.0 : (stepNumber / 3).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pedido grupal',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      restaurantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isExpired
                      ? b.walletAccent.withValues(alpha: 0.25)
                      : colors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                ),
                child: Text(
                  isExpired ? 'Caducada' : 'Paso $stepNumber de 3',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isExpired
                        ? b.onWalletAccent
                        : colors.onPrimaryContainer,
                  ),
                ),
              ),
              if (showOverflowMenu)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, color: colors.onSurfaceVariant),
                  tooltip: 'Opciones',
                  onSelected: (value) {
                    if (value == 'guest') {
                      onOpenGuestView?.call();
                    } else if (value == 'cancel') {
                      onCancelTable?.call();
                    }
                  },
                  itemBuilder: (_) => [
                    if (onOpenGuestView != null)
                      const PopupMenuItem<String>(
                        value: 'guest',
                        child: Row(
                          children: [
                            Icon(Icons.open_in_new_rounded, size: 18),
                            SizedBox(width: 10),
                            Text('Ver como invitado'),
                          ],
                        ),
                      ),
                    if (onCancelTable != null)
                      PopupMenuItem<String>(
                        value: 'cancel',
                        child: Row(
                          children: [
                            Icon(Icons.close_rounded, size: 18, color: colors.error),
                            const SizedBox(width: 10),
                            Text(
                              'Cancelar mesa',
                              style: TextStyle(color: colors.error),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: colors.primaryContainer.withValues(alpha: 0.45),
              valueColor: AlwaysStoppedAnimation<Color>(
                isExpired ? b.walletAccent : colors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepOneConfigView extends StatelessWidget {
  const _StepOneConfigView({
    required this.partySize,
    required this.minSeats,
    required this.maxSeats,
    required this.onPartySizeChanged,
    required this.selectedTimeLabel,
    required this.customTimeLabel,
    required this.estimatedTimeHhmm,
    required this.isTimeValid,
    required this.onSelectQuickMinutes,
    required this.onPickCustomTime,
    required this.selectedMode,
    required this.onModeChanged,
    required this.hasActivePlanForRestaurant,
    required this.onBlockedHostPaysTap,
    required this.hostRemainingLunches,
    required this.hasInsufficientHostLunches,
    required this.isFull,
    required this.dailyMenu,
    required this.dishSelection,
    required this.onDishChanged,
    required this.busy,
    required this.canSubmit,
    required this.onSubmit,
  });

  final int partySize;
  final int minSeats;
  final int maxSeats;
  final ValueChanged<int> onPartySizeChanged;
  final String selectedTimeLabel;
  final String? customTimeLabel;
  final String estimatedTimeHhmm;
  final bool isTimeValid;
  final ValueChanged<int> onSelectQuickMinutes;
  final VoidCallback onPickCustomTime;
  final TableMode selectedMode;
  final ValueChanged<TableMode> onModeChanged;
  final bool hasActivePlanForRestaurant;
  final VoidCallback onBlockedHostPaysTap;
  final int hostRemainingLunches;
  final bool hasInsufficientHostLunches;
  final bool isFull;
  final DailyMenu dailyMenu;
  final GroupOrderDishSelection dishSelection;
  final ValueChanged<GroupOrderDishSelection> onDishChanged;
  final bool busy;
  final bool canSubmit;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            children: [
              // 1. Cantidad de personas
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.groups_rounded, size: 20, color: colors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Personas',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: colors.onSurface,
                            ),
                          ),
                          Text(
                            'Mín. $minSeats · Máx. $maxSeats',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: IconButton.filledTonal(
                        padding: EdgeInsets.zero,
                        onPressed: partySize > minSeats
                            ? () => onPartySizeChanged(partySize - 1)
                            : null,
                        icon: const Icon(Icons.remove_rounded, size: 18),
                        tooltip: 'Menos personas',
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '$partySize',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: IconButton.filledTonal(
                        padding: EdgeInsets.zero,
                        onPressed: partySize < maxSeats
                            ? () => onPartySizeChanged(partySize + 1)
                            : null,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        tooltip: 'Más personas',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. Hora estimada de consumo
              const SocialLabel('Hora estimada de consumo'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('En 15 min'),
                    selected: selectedTimeLabel == 'En 15 min',
                    onSelected: busy ? null : (_) => onSelectQuickMinutes(15),
                  ),
                  ChoiceChip(
                    label: const Text('En 30 min'),
                    selected: selectedTimeLabel == 'En 30 min',
                    onSelected: busy ? null : (_) => onSelectQuickMinutes(30),
                  ),
                  ChoiceChip(
                    label: Text(
                      customTimeLabel != null
                          ? 'Elegir hora ($customTimeLabel)'
                          : 'Elegir hora',
                    ),
                    selected: selectedTimeLabel == 'custom',
                    onSelected: busy ? null : (_) => onPickCustomTime(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    isTimeValid ? Icons.schedule_rounded : Icons.error_outline_rounded,
                    size: 14,
                    color: isTimeValid ? colors.onSurfaceVariant : colors.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isTimeValid
                          ? 'Hora límite para completar el grupo: $estimatedTimeHhmm'
                          : 'La hora debe ser al menos 10 min mayor a la hora actual.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isTimeValid ? colors.onSurfaceVariant : colors.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3. Modalidad de pago
              const SocialLabel('Modalidad de pago'),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PaymentModeCard(
                      title: 'Cada quien lo suyo',
                      hint: 'Cada amigo descuenta de su plan o Bocadoo Wallet.',
                      selected: selectedMode == TableMode.eachOwn,
                      onTap: busy ? null : () => onModeChanged(TableMode.eachOwn),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PaymentModeCard(
                      title: 'Yo invito la mesa',
                      hint: !hasActivePlanForRestaurant
                          ? 'Requiere plan prepagado activo en este local.'
                          : 'Se descuentan $partySize almuerzos de tu plan activo ($hostRemainingLunches disponibles).',
                      disabledBadge: !hasActivePlanForRestaurant
                          ? 'Primero adquiere un plan'
                          : null,
                      disabled: !hasActivePlanForRestaurant,
                      selected: hasActivePlanForRestaurant &&
                          selectedMode == TableMode.hostPays,
                      onTap: busy
                          ? null
                          : (!hasActivePlanForRestaurant
                              ? onBlockedHostPaysTap
                              : () => onModeChanged(TableMode.hostPays)),
                    ),
                  ),
                ],
              ),
              if (hasActivePlanForRestaurant && hasInsufficientHostLunches) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.error.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 18, color: colors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tienes $hostRemainingLunches ${hostRemainingLunches == 1 ? 'almuerzo disponible' : 'almuerzos disponibles'} en tu plan (necesitas $partySize).',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (isFull) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: b.walletAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.takeout_dining_outlined, size: 18, color: b.onWalletAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Local lleno: el pedido grupal se coordinará para recoger y llevar.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: b.onWalletAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // 4. Elección del plato del anfitrión + modalidad obligatoria
              const SocialLabel('Tu plato (anfitrión)'),
              const SizedBox(height: 8),
              if (!dailyMenu.hasActiveDishes)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: b.walletAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: b.walletAccent.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.restaurant_menu_rounded,
                          size: 20, color: b.onWalletAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Menú del día no publicado. Este restaurante aún no ha publicado su menú de hoy.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: b.onWalletAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                GroupDailyMenuSelector(
                  dailyMenu: dailyMenu,
                  selection: dishSelection,
                  onChanged: onDishChanged,
                  enabled: !busy,
                  lockTakeaway: isFull,
                ),
            ],
          ),
        ),

        // 5. CTA Sticky Inferior
        Container(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            MediaQuery.paddingOf(context).bottom + 12,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
            ),
          ),
          child: ElevatedButton(
            onPressed: canSubmit && !busy ? onSubmit : null,
            child: busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: colors.onPrimary,
                    ),
                  )
                : const Text(
                    'Crear mesa y compartir link →',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ),
      ],
    );
  }
}

class _StepTwoLobbyView extends StatelessWidget {
  const _StepTwoLobbyView({
    required this.totalParticipants,
    required this.participants,
    required this.remainingDuration,
    required this.copied,
    required this.busy,
    required this.onShareWhatsApp,
    required this.onCopyLink,
    required this.onOpenGuestPreview,
    required this.onEditTableConfig,
    required this.onEditParticipantDish,
    required this.onCloseAndSendNow,
  });

  final int totalParticipants;
  final List<GroupOrderParticipant> participants;
  final Duration remainingDuration;
  final bool copied;
  final bool busy;
  final VoidCallback onShareWhatsApp;
  final VoidCallback onCopyLink;
  final VoidCallback onOpenGuestPreview;
  final VoidCallback onEditTableConfig;
  final ValueChanged<GroupOrderParticipant> onEditParticipantDish;
  final VoidCallback onCloseAndSendNow;

  String _formatCountdown(Duration d) {
    final safe = d.isNegative ? Duration.zero : d;
    final mins = safe.inMinutes;
    final secs = safe.inSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final confirmedCount = participants.length.clamp(1, totalParticipants);
    final progress = (confirmedCount / totalParticipants).clamp(0.0, 1.0);
    final slots = List<int>.generate(totalParticipants, (i) => i);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        // 1. Tarjeta de Progreso y Cuenta Regresiva
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Esperando elecciones: $confirmedCount de $totalParticipants listos',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: colors.surface,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 16, color: b.onWalletAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Caduca en ${_formatCountdown(remainingDuration)} si no se completa el grupo',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: busy ? null : onEditTableConfig,
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text('Editar datos de mesa'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. Botones de Invitación Protagonistas
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                style: compactButtonStyle(context),
                onPressed: onShareWhatsApp,
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text(
                  'Compartir por WhatsApp',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  side: BorderSide(color: colors.primary),
                ),
                onPressed: onCopyLink,
                icon: Icon(
                  copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 18,
                ),
                label: Text(
                  copied ? 'Link copiado' : 'Copiar link',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 3. Lista en Tiempo Real (En la mesa)
        Row(
          children: [
            Icon(Icons.group_outlined, size: 18, color: colors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'En la mesa ($confirmedCount/$totalParticipants)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: colors.onSurface,
                ),
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: onOpenGuestPreview,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
              label: const Text('Ver como invitado'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final idx in slots) ...[
          if (idx > 0) const SizedBox(height: 8),
          _LobbyParticipantTile(
            slotIndex: idx,
            participant: idx < participants.length ? participants[idx] : null,
            onChangeDish: idx < participants.length && !busy
                ? () => onEditParticipantDish(participants[idx])
                : null,
          ),
        ],

        // 4. Válvula de Seguridad
        if (confirmedCount >= 2) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: busy ? null : onCloseAndSendNow,
            child: Text(
              'Enviar pedido solo con los listos ($confirmedCount/$totalParticipants)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

class _StepThreeConfirmedQrView extends StatelessWidget {
  const _StepThreeConfirmedQrView({
    required this.table,
    required this.participants,
    required this.consolidatedDishes,
    required this.canCancel,
    required this.busy,
    required this.onDone,
    required this.onCancelTable,
  });

  final SharedTable table;
  final List<GroupOrderParticipant> participants;
  final List<({String name, int qty})> consolidatedDishes;
  final bool canCancel;
  final bool busy;
  final VoidCallback onDone;
  final VoidCallback onCancelTable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final confirmedCount = participants.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            children: [
              // 1. Badge de Éxito + Candado de Pedido Congelado
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: b.successContainer,
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                    border: Border.all(color: b.success.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 17, color: b.success),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Pedido enviado a cocina · Mesa #${table.shortId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: b.onSuccessContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 14,
                        color: colors.onSecondaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Pedido cerrado · No admite modificaciones',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // 2. QR Único Protagonista
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  border: Border.all(color: colors.outlineVariant),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).scaffoldBackgroundColor,
                      colors.primaryContainer,
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: b.qrBackground,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          SocialQr(
                            value: AppMode.useMock
                                ? BocadooQrParser.generateTableCode(
                                    table.id,
                                    restaurantId: table.restaurantId,
                                  )
                                : table.qrPayload,
                            size: 176,
                          ),
                          const SizedBox(height: 8),
                          SocialBadge(
                            label: 'Mesa #${table.shortId}',
                            background: colors.primaryContainer,
                            foreground: colors.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '$confirmedCount ${confirmedCount == 1 ? 'comensal confirmado' : 'comensales confirmados'} · Muestra este QR en caja para validar en 1 segundo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 3. Resumen Consolidado + Participantes
              const SocialLabel('Resumen consolidado'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < consolidatedDishes.length; i++) ...[
                      if (i > 0) Divider(height: 14, color: colors.outlineVariant),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${consolidatedDishes[i].qty}x',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: colors.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              consolidatedDishes[i].name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < participants.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _LobbyParticipantTile(
                  slotIndex: i,
                  participant: participants[i],
                ),
              ],
              const SizedBox(height: 14),

              // 4. Pie
              Text(
                'Cancelación disponible hasta 15 min antes de la hora programada (${table.time}).',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (canCancel) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: busy ? null : onCancelTable,
                  icon: Icon(Icons.close_rounded, size: 17, color: colors.error),
                  label: Text(
                    'Cancelar mesa',
                    style: TextStyle(color: colors.error),
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            MediaQuery.paddingOf(context).bottom + 12,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
            ),
          ),
          child: ElevatedButton(
            onPressed: onDone,
            child: const Text('Listo / Ver en mis pases'),
          ),
        ),
      ],
    );
  }
}

class _ExpiredOrderView extends StatelessWidget {
  const _ExpiredOrderView({
    required this.limitTimeHhmm,
    required this.onCreateNew,
  });

  final String limitTimeHhmm;
  final VoidCallback onCreateNew;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: b.walletAccent.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_off_rounded, size: 17, color: b.onWalletAccent),
                  const SizedBox(width: 6),
                  Text(
                    'Orden caducada',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: b.onWalletAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No se completó el grupo a tiempo',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Se superó la hora estimada de consumo ($limitTimeHhmm) sin que todos eligieran su plato. No se envió el pedido al restaurante y tus almuerzos/saldo retenidos han sido liberados automáticamente.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.45,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onCreateNew,
            child: const Text('Crear nuevo pedido grupal'),
          ),
        ],
      ),
    );
  }
}

class _PaymentModeCard extends StatelessWidget {
  const _PaymentModeCard({
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
    this.disabled = false,
    this.disabledBadge,
  });

  final String title;
  final String hint;
  final bool selected;
  final VoidCallback? onTap;
  final bool disabled;
  final String? disabledBadge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final card = Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: disabled
            ? colors.surfaceContainerHighest
            : (selected
                ? colors.primaryContainer.withValues(alpha: 0.6)
                : Theme.of(context).scaffoldBackgroundColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: !disabled && selected
                ? colors.primary
                : colors.outlineVariant,
            width: !disabled && selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    Icon(
                      !disabled && selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 18,
                      color: !disabled && selected
                          ? colors.primary
                          : colors.outline,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (disabledBadge != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: b.walletAccent.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      disabledBadge!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: b.onWalletAccent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return disabled ? Opacity(opacity: 0.55, child: card) : card;
  }
}

class _LobbyParticipantTile extends StatelessWidget {
  const _LobbyParticipantTile({
    required this.slotIndex,
    required this.participant,
    this.onChangeDish,
  });

  final int slotIndex;
  final GroupOrderParticipant? participant;
  final VoidCallback? onChangeDish;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final b = context.bocadooColors;
    final confirmed = participant != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: confirmed
            ? colors.primaryContainer.withValues(alpha: 0.35)
            : Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: confirmed
              ? b.success.withValues(alpha: 0.35)
              : colors.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            confirmed ? Icons.check_circle_rounded : Icons.schedule_rounded,
            size: 20,
            color: confirmed ? b.success : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        confirmed ? participant!.name : 'Cupo #${slotIndex + 1}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    if (confirmed) ...[
                      const SizedBox(width: 6),
                      SocialBadge(
                        label: participant!.isHost ? 'Anfitrión' : 'Invitado',
                        background: colors.primaryContainer,
                        foreground: colors.primary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  confirmed
                      ? participant!.selection.summary
                      : 'Esperando elección del invitado #${slotIndex + 1}...',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                confirmed ? 'Confirmado' : 'Pendiente',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: confirmed ? b.success : colors.onSurfaceVariant,
                ),
              ),
              if (confirmed && onChangeDish != null)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 26),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onChangeDish,
                  child: const Text(
                    'Cambiar mi elección',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RestaurantPickerView extends StatelessWidget {
  const _RestaurantPickerView({
    required this.restaurants,
    required this.onSelect,
  });

  final List<Restaurant> restaurants;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const SocialLabel('¿En qué restaurante vas a pedir?'),
        const SizedBox(height: 8),
        for (final r in restaurants) ...[
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              leading: CircleAvatar(
                backgroundColor: colors.primaryContainer,
                child: Icon(Icons.restaurant_rounded, color: colors.primary),
              ),
              title: Text(
                r.name,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
              subtitle: Text(
                r.zone,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.primary,
              ),
              onTap: () => onSelect(r.id),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
