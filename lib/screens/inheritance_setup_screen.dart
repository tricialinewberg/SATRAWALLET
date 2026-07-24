import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../routes.dart';
import '../services/inheritance_service.dart';
import '../services/nostr_service.dart';
import '../theme/colors.dart';
import '../widgets/glass_widgets.dart';

/// Clean inheritance dashboard, "azul vidro" direction. Editing lives in
/// three focused screens.
class InheritanceSetupScreen extends StatefulWidget {
  const InheritanceSetupScreen({super.key});

  @override
  State<InheritanceSetupScreen> createState() => _InheritanceSetupScreenState();
}

class _InheritanceSetupScreenState extends State<InheritanceSetupScreen> {
  InheritanceState? _state;
  bool _hasPassword = false;
  bool _busy = false;
  bool _confirmingLife = false;
  String? _ownerNpub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await InheritanceService.instance.getState();
    final hasPassword = await InheritanceService.instance.hasPassword();
    String? ownerNpub;
    try {
      ownerNpub = await NostrService.instance.getNpub();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _state = state;
      _hasPassword = hasPassword;
      _ownerNpub = ownerNpub;
    });
  }

  Future<void> _open(String route) async {
    await Navigator.of(context).pushNamed(route);
    await _load();
  }

  Future<void> _toggle(bool enabled) async {
    setState(() => _busy = true);
    try {
      await InheritanceService.instance.setEnabled(enabled);
      await _load();
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmLife() async {
    setState(() => _confirmingLife = true);
    try {
      final published = await InheritanceService.instance.confirmProofOfLife();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            published
                ? 'Prova de vida confirmada na rede Nostr.'
                : 'Prova criada, mas nenhum relay confirmou o recebimento.',
          ),
        ),
      );
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _confirmingLife = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      backgroundColor: SatraColors.glassVoid,
      body: SafeArea(
        child: state == null
            ? const Center(
                child: CircularProgressIndicator(color: SatraColors.glassAqua))
            : RefreshIndicator(
                color: SatraColors.glassAqua,
                backgroundColor: SatraColors.glass,
                onRefresh: _load,
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  children: [
                    _header(context),
                    const SizedBox(height: 10),
                    _hero(state),
                    const SizedBox(height: 18),
                    _progressBar(state),
                    const SizedBox(height: 18),
                    _ConfigButton(
                      icon: Icons.person_add_alt_1_outlined,
                      title: 'Herdeiros',
                      subtitle: 'Cadastrar, editar ou remover herdeiros.',
                      value: state.heirs.isEmpty
                          ? 'Pendente'
                          : '${state.heirs.length} '
                              '${state.heirs.length == 1 ? 'cadastrado' : 'cadastrados'}',
                      done: state.heirs.isNotEmpty,
                      onTap: () => _open(SatraRoutes.inheritanceHeirs),
                    ),
                    _ConfigButton(
                      icon: Icons.password_outlined,
                      title: 'Senha de liberação',
                      subtitle: 'Definir ou alterar a senha da herança.',
                      value: _hasPassword ? 'Definida' : 'Pendente',
                      done: _hasPassword,
                      onTap: () => _open(SatraRoutes.inheritancePassword),
                    ),
                    _ConfigButton(
                      icon: Icons.mail_outline,
                      title: 'Mensagem aos herdeiros',
                      subtitle: 'Escrever ou editar a primeira mensagem.',
                      value: state.inheritanceMessage ==
                              InheritanceService.defaultInheritanceMessage
                          ? 'Padrão'
                          : 'Personalizada',
                      done: state.inheritanceMessage.isNotEmpty,
                      onTap: () => _open(SatraRoutes.inheritanceMessageTest),
                    ),
                    _ConfigButton(
                      icon: Icons.schedule_outlined,
                      title: 'Carência e inatividade',
                      subtitle:
                          'Define quando o processo começa e o prazo de segurança.',
                      value:
                          '${state.inactivityDays}d + ${state.graceDays}d',
                      done: true,
                      isLast: true,
                      onTap: () => _open(SatraRoutes.inheritancePeriods),
                    ),
                    const SizedBox(height: 18),
                    _statusCard(state),
                    const SizedBox(height: 14),
                    _proofOfLifeCard(state),
                    const SizedBox(height: 14),
                    _heirsSummary(state),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _header(BuildContext context) => GlassHeader(
        title: 'Herança',
        onBack: () => Navigator.of(context).pop(),
      );

  /// A glass panel hero. Simulated glass via a subtle vertical gradient
  /// (lighter top, darker bottom), a thin luminous top edge, and a status
  /// indicator. The feature's emotional tone comes from the single aqua
  /// accent — light refracting through the tinted glass.
  Widget _hero(InheritanceState state) {
    final status = state.status;
    final (accent, dotColor, badgeLabel) = switch (status) {
      InheritanceStatus.disabled => (
        SatraColors.glassBoneDim,
        SatraColors.glassBoneDim,
        'Inativa',
      ),
      InheritanceStatus.healthy => (
        SatraColors.glassAqua,
        SatraColors.glassAqua,
        'Ativa',
      ),
      InheritanceStatus.gracePeriod => (
        SatraColors.glassAmber,
        SatraColors.glassAmber,
        'Carência',
      ),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        border: Border.all(color: SatraColors.glassFrost, width: 1),
        boxShadow: [
          BoxShadow(
            color: SatraColors.navy.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: accent.withValues(alpha: 0.35), width: 1),
                ),
                child: Icon(Icons.verified_user_outlined,
                    color: accent, size: 26),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: accent.withValues(alpha: 0.4), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration:
                          BoxDecoration(color: dotColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      badgeLabel,
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Plano de herança',
            style: TextStyle(
              color: SatraColors.glassBone,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Proteja o acesso à sua carteira para os herdeiros que você confia, '
            'com prova de vida periódica na rede Nostr.',
            style: TextStyle(
              color: SatraColors.glassBoneDim,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.bolt_outlined, color: accent, size: 15),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _heroFooter(state),
                  style: TextStyle(
                    color: SatraColors.glassBone,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _heroFooter(InheritanceState state) {
    switch (state.status) {
      case InheritanceStatus.disabled:
        final pending = <String>[];
        if (state.heirs.isEmpty) pending.add('herdeiros');
        if (!_hasPassword) pending.add('senha');
        if (pending.isEmpty) return 'Tudo pronto — ative para iniciar.';
        return 'Falta definir: ${pending.join(' e ')}.';
      case InheritanceStatus.healthy:
        final remaining = state.timeUntilInactivityThreshold;
        if (remaining == Duration.zero) return 'Prova de vida vencendo agora.';
        final days = remaining.inDays;
        if (days > 0) return 'Próxima verificação em $days dia(s).';
        final hours = remaining.inHours;
        return 'Próxima verificação em $hours hora(s).';
      case InheritanceStatus.gracePeriod:
        final remaining = state.timeUntilGraceDeadline;
        if (remaining == null || remaining == Duration.zero) {
          return 'Carência vencendo agora.';
        }
        final days = remaining.inDays;
        if (days > 0) return 'Carência: restam $days dia(s).';
        final hours = remaining.inHours;
        return 'Carência: restam $hours hora(s).';
    }
  }

  /// Glass progress bar — three segments that fill with aqua as steps are
  /// completed. The empty segments keep a faint frost tint so the bar reads
  /// as a continuous glass rail, not three disconnected dots.
  Widget _progressBar(InheritanceState state) {
    final steps = [
      state.heirs.isNotEmpty,
      _hasPassword,
      true,
    ];
    final done = steps.where((d) => d).length;
    return Semantics(
      label: 'Progresso da configuração: $done de 3 etapas concluídas',
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 3,
                decoration: BoxDecoration(
                  color: steps[i]
                      ? SatraColors.glassAqua
                      : SatraColors.glassFrost,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: steps[i]
                      ? [
                          BoxShadow(
                            color: SatraColors.glassAqua.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
            if (i < 2) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _statusCard(InheritanceState state) {
    final active = state.enabled;
    final ready = state.heirs.isNotEmpty && _hasPassword;
    final accent = active
        ? SatraColors.glassAqua
        : (ready ? SatraColors.glassBone : SatraColors.glassAmber);
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                  color: accent.withValues(alpha: 0.4), width: 1),
            ),
            child: Icon(
              active ? Icons.check_circle : Icons.shield_outlined,
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? 'Herança ativada' : 'Ativar herança',
                  style: TextStyle(
                    color: SatraColors.glassBone,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  active
                      ? 'Configuração protegida e prova de vida em andamento.'
                      : (ready
                          ? 'Tudo pronto. Ative para iniciar o monitoramento.'
                          : 'É necessário cadastrar herdeiro e senha.'),
                  style: TextStyle(
                    color: SatraColors.glassBoneDim,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_busy)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: SatraColors.glassAqua),
            )
          else
            Switch(
              value: active,
              activeThumbColor: SatraColors.glassVoid,
              activeTrackColor: SatraColors.glassAqua,
              inactiveThumbColor: SatraColors.glassBoneDim,
              inactiveTrackColor: SatraColors.glassFrost,
              onChanged: _toggle,
            ),
        ],
      ),
    );
  }

  Widget _proofOfLifeCard(InheritanceState state) => GlassSection(
        title: 'Prova de vida',
        icon: Icons.monitor_heart_outlined,
        accent: SatraColors.glassAqua,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The signature: a live ECG line in aqua that animates while the
            // feature is active — light (life) refracting through the glass.
            // Flat line when disabled; still when confirming.
            _HeartbeatPulse(active: state.enabled),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.schedule, size: 14, color: SatraColors.glassBoneDim),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    state.lastHeartbeatPublishedAt == null
                        ? 'Nenhuma confirmação publicada via Nostr.'
                        : 'Última confirmação: ${_formatDate(state.lastHeartbeatPublishedAt!.toLocal())}',
                    style: const TextStyle(
                        color: SatraColors.glassBoneDim, fontSize: 12),
                  ),
                ),
              ],
            ),
            if (_ownerNpub != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: SatraColors.glassVoid.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: SatraColors.glassFrost),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.alternate_email,
                        size: 14, color: SatraColors.glassBoneDim),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _shortNpub(_ownerNpub!),
                        style: const TextStyle(
                          color: SatraColors.glassBone,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copiar identidade Nostr',
                      iconSize: 18,
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _ownerNpub!)),
                      icon: const Icon(Icons.copy,
                          size: 16, color: SatraColors.glassBoneDim),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    state.enabled && !_confirmingLife ? _confirmLife : null,
                style: FilledButton.styleFrom(
                  backgroundColor: SatraColors.glassAqua,
                  foregroundColor: SatraColors.glassVoid,
                  disabledBackgroundColor:
                      SatraColors.glassAqua.withValues(alpha: 0.25),
                  disabledForegroundColor: SatraColors.glassBoneDim,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: _confirmingLife
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: SatraColors.glassVoid),
                      )
                    : const Icon(Icons.favorite_outline, size: 20),
                label: const Text('Confirmar prova de vida'),
              ),
            ),
          ],
        ),
      );

  Widget _heirsSummary(InheritanceState state) => GlassSection(
        title: 'Herdeiros',
        icon: Icons.family_restroom_outlined,
        accent: SatraColors.glassBoneDim,
        child: state.heirs.isEmpty
            ? Column(
                children: [
                  const SizedBox(height: 6),
                  Icon(Icons.person_add_alt_1_outlined,
                      size: 36, color: SatraColors.glassFrost),
                  const SizedBox(height: 10),
                  const Text(
                    'Nenhum herdeiro cadastrado ainda.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: SatraColors.glassBoneDim, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _open(SatraRoutes.inheritanceHeirs),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SatraColors.glassAqua,
                      side: BorderSide(
                          color: SatraColors.glassAqua.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Adicionar herdeiro'),
                  ),
                ],
              )
            : Column(
                children: [
                  for (final heir in state.heirs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _HeirChip(heir: heir),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => _open(SatraRoutes.inheritanceHeirs),
                      child: const Text('Ver todos e editar'),
                    ),
                  ),
                ],
              ),
      );

  static String _shortNpub(String value) => value.length <= 24
      ? value
      : '${value.substring(0, 14)}…${value.substring(value.length - 7)}';

  static String _formatDate(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }
}

/// Configuration row rendered as a glass tile. The icon chip turns aqua
/// when its step is complete; the value pill shifts from amber (pending)
/// to aqua (done).
class _ConfigButton extends StatelessWidget {
  const _ConfigButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onTap,
    this.done = false,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onTap;
  final bool done;
  final bool isLast;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            highlightColor: SatraColors.glassAqua.withValues(alpha: 0.08),
            splashColor: SatraColors.glassAqua.withValues(alpha: 0.12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.white,
                border: Border.all(color: SatraColors.glassFrost, width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (done
                              ? SatraColors.glassAqua
                              : SatraColors.glassBoneDim)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (done
                                ? SatraColors.glassAqua
                                : SatraColors.glassBoneDim)
                            .withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                    child: Icon(icon,
                        color: done
                            ? SatraColors.glassAqua
                            : SatraColors.glassBoneDim,
                        size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: SatraColors.glassBone,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                              color: SatraColors.glassBoneDim, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (done
                                  ? SatraColors.glassAqua
                                  : SatraColors.glassAmber)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: (done
                                    ? SatraColors.glassAqua
                                    : SatraColors.glassAmber)
                                .withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          value,
                          style: TextStyle(
                            color: done
                                ? SatraColors.glassAqua
                                : SatraColors.glassAmber,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: SatraColors.glassBoneDim, size: 20),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// A single heir shown in the dashboard summary.
class _HeirChip extends StatelessWidget {
  const _HeirChip({required this.heir});
  final TrustedContact heir;

  @override
  Widget build(BuildContext context) {
    final verified = heir.verifiedAt != null;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: SatraColors.glassFrost.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: SatraColors.glassFrost),
          ),
          child: const Icon(Icons.person_outline,
              color: SatraColors.glassBoneDim, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                heir.label,
                style: const TextStyle(
                  color: SatraColors.glassBone,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                [
                  if (heir.relationship?.isNotEmpty == true) heir.relationship!,
                  if (heir.sharePercentage != null)
                    '${heir.sharePercentage!.toStringAsFixed(0)}%',
                ].join(' · '),
                style:
                    const TextStyle(color: SatraColors.glassBoneDim, fontSize: 12),
              ),
            ],
          ),
        ),
        if (verified)
          const Icon(Icons.verified, size: 18, color: SatraColors.glassAqua),
      ],
    );
  }
}

/// The signature element: a live ECG/heartbeat line drawn in aqua that
/// sweeps repeatedly while the inheritance feature is active — a literal
/// "proof of life" rendered as light refracting through the glass. Flat
/// and dim when inactive. Uses a [CustomPainter] on a repeating
/// [AnimationController] so the trace never stalls.
class _HeartbeatPulse extends StatefulWidget {
  const _HeartbeatPulse({required this.active});
  final bool active;

  @override
  State<_HeartbeatPulse> createState() => _HeartbeatPulseState();
}

class _HeartbeatPulseState extends State<_HeartbeatPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _HeartbeatPulse old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      if (widget.active) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.active
          ? 'Prova de vida ativa — pulso em andamento'
          : 'Prova de vida inativa',
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _EcgPainter(
              progress: widget.active ? _controller.value : 0,
              active: widget.active,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

/// Draws a repeating ECG trace. The whole trace is always visible (dim),
/// and a bright "sweep" highlight travels across it when active — like a
/// vital-signs monitor where the pen draws fresh signal over a fading
/// baseline.
class _EcgPainter extends CustomPainter {
  _EcgPainter({required this.progress, required this.active});

  final double progress;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final mid = h / 2;

    // Build the ECG path: flat → small bump → QRS spike → small dip → flat.
    // The pattern repeats across the width so the sweep always has signal.
    final path = Path();
    final cycles = 3;
    final cycleW = w / cycles;
    for (var c = 0; c < cycles; c++) {
      final x0 = c * cycleW;
      _addCycle(path, x0, cycleW, mid, h);
    }

    // Baseline trace — always visible, dim.
    final basePaint = Paint()
      ..color = (active ? SatraColors.glassAqua : SatraColors.glassFrost)
          .withValues(alpha: active ? 0.25 : 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, basePaint);

    if (!active) return;

    // The bright sweep: clip to a moving window and stroke the same path
    // with full aqua + a glow, so it reads as the pen currently drawing.
    final sweepW = w * 0.32;
    final sweepX = progress * w;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(sweepX - sweepW, 0, sweepW * 2, h));
    final sweepPaint = Paint()
      ..color = SatraColors.glassAqua
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawPath(path, sweepPaint);
    // Crisp core on top of the glow.
    final corePaint = Paint()
      ..color = SatraColors.glassBone
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, corePaint);
    canvas.restore();

    // A leading dot at the sweep's front edge.
    final leadX = _pointAt(path, sweepX);
    if (leadX != null) {
      canvas.drawCircle(
        Offset(leadX.dx, leadX.dy),
        3,
        Paint()..color = SatraColors.glassBone,
      );
      canvas.drawCircle(
        Offset(leadX.dx, leadX.dy),
        6,
        Paint()
          ..color = SatraColors.glassAqua.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  void _addCycle(Path path, double x0, double cycleW, double mid, double h) {
    final p = <Offset>[];
    final seg = cycleW / 8;
    p.add(Offset(x0 + seg * 0, mid));
    p.add(Offset(x0 + seg * 1, mid));
    p.add(Offset(x0 + seg * 1.6, mid - h * 0.08)); // P wave
    p.add(Offset(x0 + seg * 2, mid));
    p.add(Offset(x0 + seg * 2.4, mid + h * 0.1)); // Q
    p.add(Offset(x0 + seg * 2.7, mid - h * 0.42)); // R spike
    p.add(Offset(x0 + seg * 3.0, mid + h * 0.14)); // S
    p.add(Offset(x0 + seg * 3.4, mid));
    p.add(Offset(x0 + seg * 4.0, mid - h * 0.05)); // T wave
    p.add(Offset(x0 + seg * 4.6, mid));
    p.add(Offset(x0 + seg * 8, mid));
    if (path.getBounds().left == 0 && path.getBounds().width == 0) {
      path.moveTo(p.first.dx, p.first.dy);
    }
    for (var i = 1; i < p.length; i++) {
      path.lineTo(p[i].dx, p[i].dy);
    }
  }

  /// Approximates the y on the path at a given x by walking the segments.
  Offset? _pointAt(Path path, double x) {
    final metrics = path.computeMetrics();
    for (final m in metrics) {
      final len = m.length;
      for (var t = 0.0; t <= 1.0; t += 0.01) {
        final offset = m.getTangentForOffset(len * t)?.position;
        if (offset != null && (offset.dx - x).abs() < 2) {
          return offset;
        }
      }
    }
    return null;
  }

  @override
  bool shouldRepaint(_EcgPainter old) =>
      old.progress != progress || old.active != active;
}
