import 'package:equatable/equatable.dart';

/// What a reward costs *Massar*, which is what decides how it is gated.
///
/// Not a difficulty or a quality tier — a 900-point fennec and a 900-point
/// voucher sit in different groups because one is a row in a table and the
/// other is somebody's stock. Physical rewards are the only kind that require
/// a real account, and the reason is in the migration: an anonymous row is
/// swept by `purge_anonymous_users` and cannot be posted a plush.
enum RewardKind {
  digital,
  partner,
  physical;

  static RewardKind parse(String? raw) => switch (raw) {
        'partner' => RewardKind.partner,
        'physical' => RewardKind.physical,
        _ => RewardKind.digital,
      };

  /// The heading this kind sits under in the catalogue.
  String get sectionTitle => switch (this) {
        RewardKind.digital => 'For the app',
        RewardKind.partner => 'Along the way',
        RewardKind.physical => 'Things to keep',
      };

  /// One line under the heading, explaining what the group *is* rather than
  /// repeating the items in it.
  String get sectionBlurb => switch (this) {
        RewardKind.digital => 'Spend points on what Massar itself can do.',
        RewardKind.partner => 'Redeemed at a place on one of your routes.',
        RewardKind.physical => 'Collected in person. Needs an account.',
      };
}

/// One row of `public.rewards`.
class Reward extends Equatable {
  const Reward({
    required this.id,
    required this.title,
    required this.blurb,
    required this.kind,
    required this.costPoints,
    this.fulfillment = 'instant',
    this.grantModelCredits = 0,
    this.grantQuestRerolls = 0,
    this.repeatable = false,
    this.stock,
    this.pickupNote,
    this.sortOrder = 0,
  });

  final String id;
  final String title;
  final String blurb;
  final RewardKind kind;
  final int costPoints;

  /// `instant` is applied by `spend_points` as it commits. `voucher` mints a
  /// code for a partner to scan — the catalogue can express it, and nothing in
  /// the app fulfils it yet.
  final String fulfillment;

  /// Generations added to `profiles.model_credits_purchased` on redemption.
  /// Applied by `spend_points` itself, inside the same transaction as the debit.
  final int grantModelCredits;

  /// Quest swaps added to the tour in progress.
  ///
  /// Applied by the client, because [AppState.taskRegenerationsLeft] is tour
  /// state that lives on the device and has no server-side counterpart. It is
  /// read from here rather than decided by a branch on [id], so adding a
  /// bigger reroll pack is a catalogue row and not a code change — and it is
  /// what makes a reroll reward buyable only while a tour is running.
  final int grantQuestRerolls;

  /// False means owning one is permanent and a second cannot be bought. The
  /// redemption row *is* the entitlement, so [ownedRewardIds] is all the app
  /// needs to know what a traveller has.
  final bool repeatable;

  /// Null is unlimited.
  final int? stock;

  final String? pickupNote;
  final int sortOrder;

  bool get isVoucher => fulfillment == 'voucher';
  bool get soldOut => stock != null && stock! <= 0;

  /// True when this reward only makes sense mid-tour.
  ///
  /// A reroll bought from the sofa would be spent into a counter that
  /// [LeaveTourEvent] resets, so the screen refuses the sale rather than taking
  /// the points for something that evaporates.
  bool get needsActiveTour => grantQuestRerolls > 0;

  factory Reward.fromJson(Map<String, dynamic> json) => Reward(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Reward',
        blurb: json['blurb'] as String? ?? '',
        kind: RewardKind.parse(json['kind'] as String?),
        costPoints: (json['cost_points'] as num?)?.toInt() ?? 0,
        fulfillment: json['fulfillment'] as String? ?? 'instant',
        grantModelCredits: (json['grant_model_credits'] as num?)?.toInt() ?? 0,
        grantQuestRerolls: (json['grant_quest_rerolls'] as num?)?.toInt() ?? 0,
        repeatable: json['repeatable'] as bool? ?? false,
        stock: (json['stock'] as num?)?.toInt(),
        pickupNote: json['pickup_note'] as String?,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [id, title, blurb, kind, costPoints, fulfillment,
        grantModelCredits, grantQuestRerolls, repeatable, stock, pickupNote,
        sortOrder];
}

/// One row of `public.redemptions` — a debit that already happened.
class Redemption extends Equatable {
  const Redemption({
    required this.id,
    required this.rewardId,
    required this.costPoints,
    required this.status,
    this.code,
    this.expiresAt,
    this.createdAt,
  });

  final String id;
  final String rewardId;
  final int costPoints;

  /// `fulfilled` for anything instant. Vouchers move `issued` → `redeemed`,
  /// or `expired` if nobody collected them.
  final String status;

  /// Present only on vouchers. Eight characters, no 0/O/1/I — it gets read
  /// aloud at a counter.
  final String? code;

  final DateTime? expiresAt;
  final DateTime? createdAt;

  factory Redemption.fromJson(Map<String, dynamic> json) => Redemption(
        id: json['id'] as String? ?? '',
        rewardId: json['reward_id'] as String? ?? '',
        costPoints: (json['cost_points'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? 'fulfilled',
        code: json['code'] as String?,
        expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      );

  @override
  List<Object?> get props => [id, rewardId, costPoints, status, code, expiresAt, createdAt];
}

/// Why a redemption did not happen.
///
/// One case per SQLSTATE that `spend_points` raises, plus the two the client
/// decides for itself. They exist as an enum rather than as message strings
/// because "you need 300 more points" and "someone took the last one" are
/// different situations that a parsed error message cannot reliably separate.
enum RedeemFailure {
  notSignedIn,
  offline,
  insufficientPoints,
  unavailable,
  outOfStock,
  alreadyOwned,
  accountRequired,
  tooMany,
  unknown;

  /// Maps the `MS0xx` codes raised by `spend_points`. Anything unrecognised is
  /// [unknown] rather than a guess.
  static RedeemFailure fromSqlState(String? code) => switch (code) {
        'MS001' => RedeemFailure.insufficientPoints,
        'MS002' => RedeemFailure.unavailable,
        'MS003' => RedeemFailure.outOfStock,
        'MS004' => RedeemFailure.alreadyOwned,
        'MS005' => RedeemFailure.accountRequired,
        'MS006' => RedeemFailure.tooMany,
        '28000' => RedeemFailure.notSignedIn,
        _ => RedeemFailure.unknown,
      };

  /// What the traveller is told. Says what happened and what to do about it —
  /// never an apology, and never "an error occurred".
  String get message => switch (this) {
        RedeemFailure.notSignedIn =>
          'Sign in first so this stays with you.',
        RedeemFailure.offline =>
          "You're offline. Redeeming needs a connection so your balance stays right.",
        RedeemFailure.insufficientPoints =>
          'Not enough points yet — finish another task or two.',
        RedeemFailure.unavailable =>
          'This one is no longer available.',
        RedeemFailure.outOfStock =>
          'The last one just went. More are on the way.',
        RedeemFailure.alreadyOwned =>
          'You already have this one.',
        RedeemFailure.accountRequired =>
          'Create an account to claim something we have to hand you in person.',
        RedeemFailure.tooMany =>
          'That is a lot of redeeming at once. Try again in a few minutes.',
        RedeemFailure.unknown =>
          "That didn't go through. Your points are untouched — try again.",
      };
}

/// The result of one redemption attempt.
///
/// A sealed pair rather than a nullable return, because the failure carries as
/// much information as the success and a null would throw it away.
sealed class RedeemResult {
  const RedeemResult();
}

class RedeemSuccess extends RedeemResult {
  const RedeemSuccess({required this.redemption, required this.balance});

  final Redemption redemption;

  /// The balance after the debit, straight from the same transaction. The
  /// screen never has to subtract for itself.
  final int balance;
}

class RedeemRejected extends RedeemResult {
  const RedeemRejected(this.reason);
  final RedeemFailure reason;
}
