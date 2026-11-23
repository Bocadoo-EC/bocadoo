import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/api_capabilities.dart';
import '../../../core/config/app_mode.dart';
import '../../../core/contracts/models.dart';
import '../../../core/theme/app_theme.dart';
import '../../customer/presentation/widgets/flash_offers_sync.dart';
import '../domain/models/cash_models.dart';
import '../../group_orders/presentation/group_order_models.dart' as go;
import '../../group_orders/presentation/widgets/daily_menu_accordion_selector.dart';
import '../domain/models/daily_menu.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_widgets.dart';

const _weekDays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _durationPresets = <(int, String)>[
  (15, '15 min'),
  (30, '30 min'),
  (45, '45 min'),
  (60, '1 hora'),
];
const _minLeadMinutes = 15;
const _stepTitles = ['¿Qué vas a liquidar?', 'Descuento y cupos', 'Vigencia'];

bool _isSentinel(String? v) => v == null || v.startsWith('Sin ');

/// O11 · Oferta flash: un plato por oferta (stepper de 3 pasos) o promo
/// programada en horas muertas. Un local puede publicar N ofertas flash.
class FlashOfferSheet extends ConsumerStatefulWidget {
  const FlashOfferSheet({super.key});

  @override
  ConsumerState<FlashOfferSheet> createState() => _FlashOfferSheetState();
}

class _FlashOfferSheetState extends ConsumerState<FlashOfferSheet> {
  OfferKind _kind = OfferKind.flash;

  // Flash · paso 1
  int _step = 0;
  go.GroupOrderDishSelection _sel = const go.GroupOrderDishSelection();

  // Flash · paso 2
  int? _flashDiscount = 10;
  int? _flashSlots = 10;
  final _slotsOther = TextEditingController();

  // Flash · paso 3: duración por defecto 30 min (`null` = Otra hora)
  int? _durationMinutes = 30;
  DateTime? _customUntil;
  bool _customInvalid = false;

  // Promo programada
  final _title = TextEditingController();
  final Set<int> _days = {2, 4};
  TimeOfDay _from = const TimeOfDay(hour: 16, minute: 0);
  TimeOfDay _to = const TimeOfDay(hour: 18, minute: 0);
  int? _progDiscount = 20;
  int _progSlots = 20;

  final _manual = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.invalidate(posMenuProvider);
    });
  }

  @override
  void dispose() {
    _slotsOther.dispose();
    _title.dispose();
    _manual.dispose();
    super.dispose();
  }

  bool get _isFlash => _kind == OfferKind.flash;

  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  int _discountOf(int? preset) {
    if (preset != null) return preset;
    return (int.tryParse(_manual.text) ?? 0).clamp(0, 90);
  }

  int get _discount => _discountOf(_isFlash ? _flashDiscount : _progDiscount);

  int get _slots {
    if (!_isFlash) return _progSlots;
    return _flashSlots ?? (int.tryParse(_slotsOther.text) ?? 0);
  }

  // ── Menú de hoy y precios reales desde Ajustes ───────────────────────────

  List<DailyMenuCourse> _coursesOf(DailyMenu? menu, String category) {
    if (menu == null || !menu.isPublished) return const [];
    return [
      for (final c in menu.courses)
        if (!c.isSoldOut && c.category.trim().toLowerCase() == category) c,
    ];
  }

  go.DailyMenu _toSelectorMenu(DailyMenu menu) {
    List<String> names(String category) =>
        [for (final c in _coursesOf(menu, category)) c.name];
    final mains = names('fuerte');
    return go.DailyMenu(
      restaurantId: menu.restaurantId,
      restaurantName: '',
      soups: names('sopa'),
      mains: mains,
      drinks: [...names('jugo'), ...names('bebida')],
      desserts: names('postre'),
      mainTags: {
        for (final m in mains)
          if (m.toLowerCase().contains('fit')) m: 'Fit',
      },
      isPublished: true,
    );
  }

  bool get _hasSoup => !_isSentinel(_sel.soup);
  bool get _hasMain => !_isSentinel(_sel.main);
  bool get _hasDrink => !_isSentinel(_sel.drink);
  bool get _hasDessert => !_isSentinel(_sel.dessert);

  /// Ítems elegidos, sin "Sin sopa" / "Sin segundo" / "Sin bebida" / "Sin postre".
  List<String> get _chosenItems => [
        for (final v in [_sel.soup, _sel.main, _sel.drink, _sel.dessert])
          if (!_isSentinel(v)) v!,
      ];

  String get _comboTitle {
    final t = _chosenItems.join(' + ');
    return t.length <= 80 ? t : '${t.substring(0, 79)}…';
  }

  double? _coursePrice(DailyMenu? menu, String category, String? name) {
    if (name == null || _isSentinel(name)) return null;
    final p = _coursesOf(menu, category)
        .where((c) => c.name == name)
        .firstOrNull
        ?.price;
    return (p != null && p > 0) ? p : null;
  }

  double _soupPrice(DailyMenu? menu, ExecutivePrices prices) =>
      _coursePrice(menu, 'sopa', _sel.soup) ?? prices.soloSoup;

  double _mainPrice(DailyMenu? menu, ExecutivePrices prices) =>
      _coursePrice(menu, 'fuerte', _sel.main) ?? prices.soloSecond;

  double _drinkExtraPrice(DailyMenu? menu) {
    if (!_hasDrink) return 0;
    return _coursePrice(menu, 'jugo', _sel.drink) ??
        _coursePrice(menu, 'bebida', _sel.drink) ??
        0;
  }

  double _dessertExtraPrice(DailyMenu? menu) {
    if (!_hasDessert) return 0;
    return _coursePrice(menu, 'postre', _sel.dessert) ?? 0;
  }

  /// Calcula el precio base real usando Ajustes (`executivePricesProvider`):
  /// - Sopa + Segundo = `precioAlmuerzoCentavos` (`prices.lunch`)
  /// - Solo Segundo = `precioSegundoCentavos` (`prices.soloSecond` o precio del plato)
  /// - Solo Sopa = `precioSopaCentavos` (`prices.soloSoup` o precio del plato)
  /// - Bebida / Postre del día = `$0,00` adicional salvo que tenga precio propio.
  double _basePrice(ExecutivePrices prices, DailyMenu? menu) {
    final extras = _drinkExtraPrice(menu) + _dessertExtraPrice(menu);
    final double core;
    if (_hasSoup && _hasMain) {
      core = prices.lunch;
    } else if (_hasMain) {
      core = _mainPrice(menu, prices);
    } else {
      core = _soupPrice(menu, prices);
    }
    final total = core + extras;
    return total > 0 ? total : 0.01;
  }

  String? _dishIdFor(DailyMenu? menu) {
    final name = _hasMain ? _sel.main : _sel.soup;
    final category = _hasMain ? 'fuerte' : 'sopa';
    return _coursesOf(menu, category).where((c) => c.name == name).firstOrNull?.dishId;
  }

  // ── Vigencia basada en `DateTime.now()` ─────────────────────────────────

  DateTime? _effectiveValidUntil(DateTime now) {
    if (_durationMinutes != null) {
      return now.add(Duration(minutes: _durationMinutes!));
    }
    final custom = _customUntil;
    if (custom == null || _customInvalid) return null;
    return custom;
  }

  static bool _meetsMinLead(TimeOfDay picked, DateTime now) {
    final pickedMins = picked.hour * 60 + picked.minute;
    final nowMins = now.hour * 60 + now.minute;
    return pickedMins - nowMins >= _minLeadMinutes;
  }

  Future<void> _pickCustomLimit() async {
    final now = DateTime.now();
    final initialDt = _customUntil != null && !_customInvalid
        ? _customUntil!
        : now.add(const Duration(minutes: 30));
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDt),
    );
    if (picked == null || !mounted) return;
    final checkNow = DateTime.now();
    if (!_meetsMinLead(picked, checkNow)) {
      setState(() {
        _durationMinutes = null;
        _customUntil = null;
        _customInvalid = true;
        _error =
            'La hora límite debe ser al menos $_minLeadMinutes minutos mayor a la hora actual.';
      });
      return;
    }
    setState(() {
      _durationMinutes = null;
      _customUntil = DateTime(
        checkNow.year,
        checkNow.month,
        checkNow.day,
        picked.hour,
        picked.minute,
      );
      _customInvalid = false;
      _error = null;
    });
  }

  Future<void> _pickTime(bool from) async {
    final picked = await showTimePicker(context: context, initialTime: from ? _from : _to);
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  // ── Flujo del stepper ────────────────────────────────────────────────────

  bool _validateStep(double? base) {
    if (_step == 0) return _hasSoup || _hasMain;
    if (_step == 1) {
      final discount = _discount;
      if (discount <= 0) {
        setState(() => _error = 'Elige un descuento');
        return false;
      }
      if (base == null || base * (100 - discount) / 100 >= base) {
        setState(() => _error = 'El precio de oferta debe ser menor al precio normal');
        return false;
      }
      final slots = _slots;
      if (slots < 1 || slots > 1000) {
        setState(() => _error = 'Los cupos deben estar entre 1 y 1000');
        return false;
      }
      return true;
    }
    return true;
  }

  void _next(double? base) {
    FocusScope.of(context).unfocus();
    if (!_validateStep(base)) return;
    setState(() {
      _error = null;
      _step += 1;
    });
  }

  void _back() {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _step -= 1;
    });
  }

  // ── Publicación ──────────────────────────────────────────────────────────

  Future<void> _publish({required double base, String? dishId}) async {
    final discount = _discount;
    if (discount <= 0) {
      setState(() => _error = 'Elige un descuento');
      return;
    }
    if (!_isFlash && _days.isEmpty) {
      setState(() => _error = 'Elige al menos un día');
      return;
    }
    if (!_isFlash && _minutes(_from) >= _minutes(_to)) {
      setState(() => _error = 'La hora de inicio debe ser antes del final');
      return;
    }

    final now = DateTime.now();
    final DateTime? validUntilDt = _isFlash ? _effectiveValidUntil(now) : null;
    if (_isFlash && validUntilDt == null) {
      setState(() {
        _error =
            'Elige una duración o una hora al menos $_minLeadMinutes minutos mayor a la actual.';
      });
      return;
    }
    if (_isFlash &&
        _durationMinutes == null &&
        !_meetsMinLead(TimeOfDay.fromDateTime(validUntilDt!), now)) {
      setState(() {
        _customInvalid = true;
        _error =
            'La hora límite debe ser al menos $_minLeadMinutes minutos mayor a la hora actual.';
      });
      return;
    }

    final price = (base * (100 - discount) / 100 * 100).roundToDouble() / 100;
    final slots = _slots;
    final dishName = _comboTitle;
    final validTime =
        validUntilDt != null ? TimeOfDay.fromDateTime(validUntilDt) : null;

    if (_isFlash) {
      final active = ref.read(activeOffersProvider).value ?? const <FlashOffer>[];
      final duplicated = active.any(
        (o) =>
            o.kind == OfferKind.flash &&
            o.title.trim().toLowerCase() == dishName.toLowerCase(),
      );
      if (duplicated) {
        setState(() => _error = 'Ya tienes una oferta activa para "$dishName"');
        return;
      }
    }

    final offer = _isFlash
        ? FlashOffer(
            kind: OfferKind.flash,
            title: dishName,
            dishId: dishId,
            discountPercent: discount,
            slots: slots,
            slotsTotal: slots,
            price: price,
            originalPrice: base,
            validUntil: _hhmm(validTime!),
            endsAt: validUntilDt,
          )
        : FlashOffer(
            kind: OfferKind.programada,
            title: _title.text.trim().isEmpty ? 'Promo programada' : _title.text.trim(),
            discountPercent: discount,
            slots: slots,
            price: price,
            days: (_days.toList()..sort()),
            fromMinutes: _minutes(_from),
            toMinutes: _minutes(_to),
          );

    setState(() {
      _sending = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(ownerCashRepositoryProvider);
    final rid = ref.read(ownerRestaurantIdProvider);
    final offerId = await repo.publishOffer(rid, offer);
    if (!mounted) return;
    if (offerId == null) {
      final apiErr = AppMode.useMock
          ? null
          : ref.read(apiOwnerRepositoryProvider).consumeLastError();
      setState(() {
        _sending = false;
        _error = apiErr ?? 'No se pudo publicar la oferta';
      });
      return;
    }
    container.invalidate(activeOffersProvider);
    if (_isFlash && validUntilDt != null) {
      FlashOffersLiveSync.instance.notifyPublished(
        restaurantId: rid,
        offer: RestaurantOffer(
          id: offerId,
          restaurantId: rid,
          title: dishName,
          badge: discount > 0 ? '-$discount% · $dishName' : dishName,
          price: price,
          originalPrice: base,
          slotsLeft: slots,
          availableNow: true,
          appliesToday: true,
          reservable: false,
          endsAt: validUntilDt,
        ),
      );
    }
    navigator.pop(true);
    showUndoSnackBar(
      messenger,
      label: _isFlash ? '$dishName · $slots cupos publicados' : 'Promo publicada ($slots cupos)',
      onUndo: () async {
        await repo.cancelOffer(rid, offerId: offerId);
        FlashOffersLiveSync.instance.notifyRemoved(
          restaurantId: rid,
          offerId: offerId,
        );
        container.invalidate(activeOffersProvider);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final prices = ref.watch(executivePricesProvider);
    final menuAsync = ref.watch(posMenuProvider);
    final menu = menuAsync.value;
    final menuLoaded = menuAsync.hasValue || menuAsync.hasError;
    final menuOk = (menu?.isPublished ?? false) &&
        (_coursesOf(menu, 'sopa').isNotEmpty || _coursesOf(menu, 'fuerte').isNotEmpty);
    final blocked = _isFlash && menuLoaded && !menuOk;

    final double base = _isFlash ? _basePrice(prices, menu) : prices.lunch;
    final discount = _discount;
    final newPrice = base * (100 - discount) / 100;
    final lastStep = _step == _stepTitles.length - 1;
    final now = DateTime.now();
    final validUntilDt = _effectiveValidUntil(now);
    final validUntilValid = validUntilDt != null && !_customInvalid;
    final publishDisabled =
        _sending || (lastStep && _isFlash && !validUntilValid);

    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final sysNav = MediaQuery.viewPaddingOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final navClearance =
        keyboard > 0 ? 0.0 : (sysNav - safeBottom).clamp(0.0, double.infinity);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, navClearance + 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _isFlash ? Icons.bolt_rounded : Icons.event_repeat_rounded,
                        size: 20,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Oferta flash',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (ApiCapabilities.flashScheduledOffer) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _KindTab(
                            icon: Icons.bolt_rounded,
                            title: 'Flash de hoy',
                            subtitle: 'Liquidación de excedentes',
                            selected: _isFlash,
                            onTap: () => setState(() {
                              _kind = OfferKind.flash;
                              _error = null;
                            }),
                          ),
                        ),
                        Expanded(
                          child: _KindTab(
                            icon: Icons.calendar_month_rounded,
                            title: 'Horas muertas',
                            subtitle: 'Promo programada',
                            selected: !_isFlash,
                            onTap: () => setState(() {
                              _kind = OfferKind.programada;
                              _error = null;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (blocked)
                  _BlockedMenuNotice(
                    onGoToMenu: () {
                      final router = GoRouter.of(context);
                      Navigator.of(context).pop();
                      router.go('/owner/menu');
                    },
                  )
                else if (_isFlash && !menuLoaded)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_isFlash) ...[
                  _StepHeader(step: _step, titles: _stepTitles),
                  const SizedBox(height: 14),
                  if (_step == 0) ..._stepOne(menu!, prices, base),
                  if (_step == 1) ..._stepTwo(base: base, newPrice: newPrice),
                  if (_step == 2)
                    ..._stepThree(
                      dishName: _comboTitle,
                      base: base,
                      newPrice: newPrice,
                      validUntilDt: validUntilDt,
                    ),
                ] else ...[
                  Text(
                    'Atrae clientes en los días y horas de poco movimiento. Se repite cada semana durante 30 días.',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ..._scheduledFields(),
                  const SizedBox(height: 14),
                  _discountSection(
                    base: base,
                    newPrice: newPrice,
                    presets: const [10, 20, 30],
                  ),
                  const SizedBox(height: 14),
                  const _Label('Cupos disponibles'),
                  _OptionRow(
                    options: [for (final s in const [10, 20, 30]) ('$s cupos', s)],
                    selected: _progSlots,
                    onSelect: (v) => setState(() => _progSlots = v!),
                  ),
                  const SizedBox(height: 14),
                  const _InfoBox(
                    'La promo queda vigente 30 días. Puedes cancelarla cuando quieras.',
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.bocadooColors.danger,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (blocked || (_isFlash && !menuLoaded))
                  const SizedBox.shrink()
                else if (!_isFlash)
                  ElevatedButton(
                    onPressed:
                        _sending ? null : () => _publish(base: prices.lunch),
                    child: const Text('Publicar promo programada'),
                  )
                else
                  Row(
                    children: [
                      if (_step > 0) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _sending ? null : _back,
                            child: const Text('Atrás'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: publishDisabled ||
                                  (_step == 0 && !(_hasSoup || _hasMain))
                              ? null
                              : lastStep
                                  ? () => _publish(
                                        base: base,
                                        dishId: _dishIdFor(menu),
                                      )
                                  : () => _next(base),
                          child: Text(
                            lastStep ? 'Publicar oferta flash' : 'Siguiente',
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Paso 1 · ¿Qué del menú de hoy vas a liquidar? ──────────────────────

  List<Widget> _stepOne(DailyMenu menu, ExecutivePrices prices, double base) {
    final colors = context.colorScheme;
    final canPrice = _hasSoup || _hasMain;
    final soupPrice = _soupPrice(menu, prices);
    final mainPrice = _mainPrice(menu, prices);
    final drinkExtra = _drinkExtraPrice(menu);
    final dessertExtra = _dessertExtraPrice(menu);

    return [
      Text(
        'Arma 1 oferta con los platos de tu menú de hoy. Elige al menos una sopa o un segundo.',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.35,
          color: colors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 12),
      DailyMenuAccordionSelector(
        flashMode: true,
        dailyMenu: _toSelectorMenu(menu),
        selection: _sel,
        soupPriceLabel: OwnerFormat.money(soupPrice),
        mainPriceLabel: OwnerFormat.money(mainPrice),
        drinkPriceLabel:
            drinkExtra > 0 ? OwnerFormat.money(drinkExtra) : 'Incluido',
        dessertPriceLabel:
            dessertExtra > 0 ? OwnerFormat.money(dessertExtra) : 'Incluido',
        onChanged: (next) => setState(() {
          _sel = next;
          _error = null;
        }),
      ),
      const SizedBox(height: 10),
      _InfoBox(
        canPrice
            ? '$_comboTitle\nPrecio base: ${OwnerFormat.money(base)}'
            : 'Elige una sopa o un segundo para continuar',
      ),
    ];
  }

  // ── Paso 2 · Descuento y cupos ──────────────────────────────────────────

  List<Widget> _stepTwo({required double? base, required double? newPrice}) {
    return [
      _discountSection(base: base, newPrice: newPrice, presets: const [10, 20]),
      const SizedBox(height: 14),
      const _Label('Cupos disponibles'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in const [5, 10, 15])
          _ChipChoice(
            label: '$s cupos',
            selected: _flashSlots == s,
            onTap: () => setState(() {
              _flashSlots = s;
              _error = null;
            }),
          ),
        _ChipChoice(
          label: 'Otro',
          selected: _flashSlots == null,
          onTap: () => setState(() {
            _flashSlots = null;
            _error = null;
          }),
        ),
      ]),
      if (_flashSlots == null) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _slotsOther,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Cantidad de cupos',
            suffixText: 'cupos',
          ),
        ),
      ],
      const SizedBox(height: 8),
      Text(
        'Cada cupo emite 1 pase QR exclusivo de Oferta Flash y se bloquea al agotarse.',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  Widget _discountSection({
    required double? base,
    required double? newPrice,
    required List<int> presets,
  }) {
    final colors = context.colorScheme;
    final selected = _isFlash ? _flashDiscount : _progDiscount;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Label(
        'Descuento',
        trailing: base == null || newPrice == null
            ? null
            : Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: OwnerFormat.money(base),
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  TextSpan(
                    text: '  ${OwnerFormat.money(newPrice)} · -$_discount%',
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ]),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
      ),
      _OptionRow(
        options: [for (final d in presets) ('-$d %', d), ('Manual', null)],
        selected: selected,
        onSelect: (v) => setState(() {
          if (_isFlash) {
            _flashDiscount = v;
          } else {
            _progDiscount = v;
          }
          _error = null;
        }),
      ),
      if (selected == null) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _manual,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Descuento en %',
            suffixText: '%',
          ),
        ),
      ],
      if (newPrice != null) ...[
        const SizedBox(height: 8),
        _InfoBox(
          'Precio de oferta: ${OwnerFormat.money(newPrice)} por plato',
          centered: true,
        ),
      ],
    ]);
  }

  // ── Paso 3 · Vigencia y vista previa ────────────────────────────────────

  List<Widget> _stepThree({
    required String dishName,
    required double? base,
    required double? newPrice,
    required DateTime? validUntilDt,
  }) {
    final colors = context.colorScheme;
    final validTime =
        validUntilDt != null ? TimeOfDay.fromDateTime(validUntilDt) : null;
    final isCustomSelected = _durationMinutes == null;

    return [
      const _Label('Duración desde ahora'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (mins, label) in _durationPresets)
            _ChipChoice(
              label: label,
              selected: _durationMinutes == mins,
              onTap: () => setState(() {
                _durationMinutes = mins;
                _customUntil = null;
                _customInvalid = false;
                _error = null;
              }),
            ),
          _ChipChoice(
            label: isCustomSelected && validTime != null
                ? 'Hasta ${_hhmm(validTime)}'
                : 'Otra hora',
            icon: Icons.schedule_rounded,
            selected: isCustomSelected,
            onTap: _pickCustomLimit,
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        validTime != null
            ? 'Válida desde ahora hasta las ${_hhmm(validTime)}'
            : 'Elige una hora al menos $_minLeadMinutes minutos mayor a la hora actual.',
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: validTime != null
              ? colors.primary
              : context.bocadooColors.danger,
        ),
      ),
      const SizedBox(height: 14),
      const _Label('Así la verá el comensal'),
      _OfferPreview(
        dishName: dishName,
        originalPrice: base,
        price: newPrice,
        slots: _slots,
        until: validTime,
      ),
    ];
  }

  // ── Promo programada ────────────────────────────────────────────────────

  List<Widget> _scheduledFields() {
    final colors = context.colorScheme;
    return [
      const _Label('Título de la promo'),
      TextField(
        controller: _title,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Ej. Almuerzo ejecutivo a precio especial'),
      ),
      const SizedBox(height: 14),
      const _Label('Días de la semana'),
      Row(children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Material(
              color: _days.contains(i + 1) ? colors.primary : colors.primaryContainer.withValues(alpha: 0.45),
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => setState(() {
                  _days.contains(i + 1) ? _days.remove(i + 1) : _days.add(i + 1);
                  _error = null;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text(
                    _weekDays[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _days.contains(i + 1) ? colors.onPrimary : colors.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 14),
      const _Label('Rango horario'),
      Row(children: [
        Expanded(child: _TimeField(label: 'Desde', value: _hhmm(_from), onTap: () => _pickTime(true))),
        const SizedBox(width: 10),
        Expanded(child: _TimeField(label: 'Hasta', value: _hhmm(_to), onTap: () => _pickTime(false))),
      ]),
    ];
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.titles});

  final int step;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (var i = 0; i < titles.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 4,
              decoration: BoxDecoration(
                color: i <= step ? colors.primary : colors.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 10),
      Text(
        'Paso ${step + 1} de ${titles.length}',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant),
      ),
      const SizedBox(height: 2),
      Text(
        titles[step],
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: colors.onSurface),
      ),
    ]);
  }
}

class _BlockedMenuNotice extends StatelessWidget {
  const _BlockedMenuNotice({required this.onGoToMenu});

  final VoidCallback onGoToMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      Icon(Icons.restaurant_menu_rounded, size: 36, color: colors.onSurfaceVariant),
      const SizedBox(height: 12),
      Text(
        'Primero publica tu menú del día para crear una oferta flash',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: colors.onSurface),
      ),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: onGoToMenu, child: const Text('Ir a mi menú')),
    ]);
  }
}

class _ChipChoice extends StatelessWidget {
  const _ChipChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 84),
      child: OwnerChoice(label: label, icon: icon, selected: selected, onTap: onTap),
    );
  }
}

class _OfferPreview extends StatelessWidget {
  const _OfferPreview({
    required this.dishName,
    required this.originalPrice,
    required this.price,
    required this.slots,
    required this.until,
  });

  final String dishName;
  final double? originalPrice;
  final double? price;
  final int slots;
  final TimeOfDay? until;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.bolt_rounded, size: 13, color: colors.onPrimary),
            const SizedBox(width: 2),
            Text('OFERTA FLASH',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: colors.onPrimary)),
          ]),
        ),
        const SizedBox(height: 8),
        Text(
          dishName.isEmpty ? 'Tu plato' : dishName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: colors.onSurface),
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(children: [
            if (originalPrice != null)
              TextSpan(
                text: OwnerFormat.money(originalPrice!),
                style: TextStyle(color: colors.onSurfaceVariant, decoration: TextDecoration.lineThrough),
              ),
            if (price != null)
              TextSpan(
                text: '  ${OwnerFormat.money(price!)}',
                style: TextStyle(color: colors.primary, fontWeight: FontWeight.w900),
              ),
          ]),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          'Quedan $slots cupos${until == null ? '' : ' · Hasta ${_FlashOfferSheetState._hhmm(until!)}'}',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant),
        ),
      ]),
    );
  }
}

class _KindTab extends StatelessWidget {
  const _KindTab({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final fg = selected ? colors.onPrimary : colors.onSurface;
    return Material(
      color: selected ? colors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: selected ? fg : colors.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: fg)),
              ),
            ]),
            Text(subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.85))),
          ]),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: context.colorScheme.onSurface)),
        ),
        ?trailing,
      ]),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.options, required this.selected, required this.onSelect});

  final List<(String, int?)> options;
  final int? selected;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (var i = 0; i < options.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: OwnerChoice(
            label: options[i].$1,
            selected: options[i].$2 == selected,
            onTap: () => onSelect(options[i].$2),
          ),
        ),
      ],
    ]);
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox(this.text, {this.centered = false});

  final String text;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTheme.inputRadius),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(
        text,
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          fontSize: 13,
          fontWeight: centered ? FontWeight.w800 : FontWeight.w600,
          color: centered ? colors.onSurface : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.onSurfaceVariant)),
      const SizedBox(height: 4),
      Material(
        color: colors.primaryContainer.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.inputRadius),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.inputRadius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Expanded(
                child: Text(value,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: colors.onSurface)),
              ),
              Icon(Icons.schedule_rounded, size: 18, color: colors.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    ]);
  }
}
