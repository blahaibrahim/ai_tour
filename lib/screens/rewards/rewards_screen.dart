import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../models/reward.dart';
import '../../repositories/rewards_repository.dart';
import '../../services/backend_monitor.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';
import 'widgets/balance_header.dart';
import 'widgets/redeem_sheet.dart';
import 'widgets/reward_card.dart';

/// What points are for.
///
/// The catalogue, the wallet, and one button per row. It holds its own state
/// rather than going through `AppBloc`: nothing else in the app needs to know
/// what is on sale, and a screen that is opened, scrolled and closed is exactly
/// the case a bloc adds ceremony to. The one thing that *is* shared — the
/// balance — comes from [AppState] and is refreshed through [LoadPointsEvent]
/// after a redemption, so the number in Settings and the number here cannot
/// disagree.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  List<Reward> _catalogue = const [];
  Set<String> _owned = const {};
  bool _loading = true;

  /// The reward currently being bought, if any. Held as an id rather than a
  /// bool so only the row that was pressed shows a spinner — a screen-wide
  /// blocking overlay for a one-second call is heavier than the action.
  String? _redeeming;

  @override
  void initState() {
    super.initState();
    _load();
    // The balance may be stale — earned on another device, or spent on this one
    // before the screen was last closed. Asking on open costs one round trip
    // and prevents the worst failure this screen has, which is offering
    // something the traveller cannot actually afford.
    context.read<AppBloc>().add(const LoadPointsEvent());
  }

  Future<void> _load() async {
    final catalogue = await RewardsRepository.fetchCatalogue();
    final owned = await RewardsRepository.ownedRewardIds();
    if (!mounted) return;
    setState(() {
      _catalogue = catalogue;
      _owned = owned;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final balance = context.select<AppBloc, int?>((b) => b.state.pointsBalance);
    final onTour = context.select<AppBloc, bool>((b) => b.state.routeAccepted);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Rewards'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.ink),
        titleTextStyle: const TextStyle(
          color: AppTheme.ink,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      body: AppBackdrop(
        variant: AppBackdropVariant.warm,
        child: RefreshIndicator(
          onRefresh: () async {
            context.read<AppBloc>().add(const LoadPointsEvent());
            await _load();
          },
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.space5, 100, AppTheme.space5, 48),
                  children: [
                    BalanceHeader(balance: balance),
                    AppTheme.gap6,
                    if (_catalogue.isEmpty)
                      const _EmptyCatalogue()
                    else
                      ..._sections(balance, onTour),
                  ],
                ),
        ),
      ),
    );
  }

  /// One block per [RewardKind], in catalogue order, skipping any kind with
  /// nothing in it — an empty "Things to keep" heading promises stock that does
  /// not exist.
  List<Widget> _sections(int? balance, bool onTour) {
    final widgets = <Widget>[];
    for (final kind in RewardKind.values) {
      final items = _catalogue.where((r) => r.kind == kind).toList();
      if (items.isEmpty) continue;

      if (widgets.isNotEmpty) widgets.add(AppTheme.gap6);
      widgets.add(_SectionHeader(kind: kind));
      widgets.add(AppTheme.gap3);
      for (final reward in items) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.space3),
          child: RewardCard(
            reward: reward,
            owned: _owned.contains(reward.id) && !reward.repeatable,
            // Unknown balance is not treated as zero: the card shows the price
            // without claiming the traveller cannot afford it, and the tap is
            // rejected by the server if it turns out they cannot.
            affordable: balance == null || balance >= reward.costPoints,
            busy: _redeeming == reward.id,
            // A reroll spends into a counter that only exists during a tour.
            // Selling one now would take the points and give nothing back.
            blockedNote: reward.needsActiveTour && !onTour
                ? 'Available once you are walking a route.'
                : null,
            onTap: () => _confirm(reward, balance),
          ),
        ));
      }
    }
    return widgets;
  }

  Future<void> _confirm(Reward reward, int? balance) async {
    if (_redeeming != null) return;

    final proceed = await showRedeemSheet(
      context,
      reward: reward,
      balance: balance,
    );
    if (proceed != true || !mounted) return;

    // Checked here rather than left to the round trip so the message is the
    // true one. Without this, an offline tap surfaces as a generic failure
    // several seconds later.
    if (BackendMonitor.instance.isOffline) {
      _report(RedeemFailure.offline.message);
      return;
    }

    setState(() => _redeeming = reward.id);
    final result = await RewardsRepository.redeem(reward);
    if (!mounted) return;
    setState(() => _redeeming = null);

    switch (result) {
      case RedeemSuccess(:final redemption):
        // Refetched rather than patched from the returned balance: the same
        // event also drains the outbox, and one source for the number means the
        // header and Settings cannot drift apart.
        final bloc = context.read<AppBloc>();
        bloc.add(const LoadPointsEvent());
        // The credits were applied by `spend_points` inside the debit's own
        // transaction. Rerolls are tour state, which lives nowhere but here.
        if (reward.grantQuestRerolls > 0) {
          bloc.add(GrantQuestRerollsEvent(reward.grantQuestRerolls));
        }
        setState(() => _owned = {..._owned, reward.id});
        _report(_successMessage(reward, redemption));
      case RedeemRejected(:final reason):
        // A rejection means nothing was charged — every failure path in
        // `spend_points` raises before or instead of the debit, and a raise
        // rolls the whole function back.
        _report(reason.message);
        if (reason == RedeemFailure.insufficientPoints ||
            reason == RedeemFailure.alreadyOwned) {
          context.read<AppBloc>().add(const LoadPointsEvent());
        }
    }
  }

  String _successMessage(Reward reward, Redemption redemption) {
    if (redemption.code != null) {
      return 'Voucher ${redemption.code} is in your rewards. Show it to collect.';
    }
    if (reward.grantModelCredits > 0) {
      final n = reward.grantModelCredits;
      return n == 1
          ? 'One scan credit added. It does not expire.'
          : '$n scan credits added. They do not expire.';
    }
    if (reward.grantQuestRerolls > 0) {
      final n = reward.grantQuestRerolls;
      return n == 1
          ? 'One more quest swap on this tour.'
          : '$n more quest swaps on this tour.';
    }
    return '${reward.title} is yours.';
  }

  void _report(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.kind});

  final RewardKind kind;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kind.sectionTitle.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: AppTheme.text.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          kind.sectionBlurb,
          style: TextStyle(
            fontSize: 12.5,
            color: AppTheme.text.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

/// Shown when the catalogue comes back empty, which in practice means Supabase
/// could not be reached — [RewardsRepository] returns an empty list rather than
/// throwing. Worded for the traveller, who does not care which of those it was.
class _EmptyCatalogue extends StatelessWidget {
  const _EmptyCatalogue();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.card_giftcard_outlined,
              size: 40, color: AppTheme.text.withValues(alpha: 0.3)),
          AppTheme.gap4,
          Text(
            'Nothing to spend on right now',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.text.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pull down to check again once you have a connection.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.text.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
