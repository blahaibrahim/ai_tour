import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/app/app_bloc.dart';
import '../../blocs/app/app_event.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_notification.dart';
import '../../repositories/notification_inbox_repository.dart';
import '../../theme.dart';
import '../../widgets/app_backdrop.dart';
import '../splat_viewer/splat_viewer_screen.dart';

/// Everything the app has told this traveller, oldest still kept at the bottom.
///
/// The inbox exists because a push notification is not a record of anything: it
/// lives in the tray until the tray is swiped and then it is gone, so "your
/// footage became a 3D scene" — which is an invitation to go and look at
/// something, not a status update — was unrecoverable the moment it was
/// dismissed. `public.user_notifications` is the durable copy and this screen is
/// its reader.
///
/// Deletes are the traveller's, per-row and all-at-once, and they are real
/// deletes rather than a hidden flag: RLS gives them `delete` on their own rows
/// (supabase/migrations/20260819120000), and a "cleared" list that the server
/// still holds would be a promise the app cannot keep.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await NotificationInboxRepository.fetchAll();
    if (!mounted) return;
    setState(() => _items = items);

    // Opening the screen is what "read" means here — the whole list is on
    // screen, so marking rows read one at a time as they scroll past would be
    // measuring scrolling rather than reading. Fired after the list is shown so
    // the write is never something the traveller waits on.
    if (items.any((item) => item.isUnread)) {
      await NotificationInboxRepository.markAllRead();
      if (mounted) context.read<AppBloc>().add(const RefreshUnreadCountEvent());
    }
  }

  Future<void> _remove(AppNotification item) async {
    // Removed from the list first: a swipe that leaves the row in place while a
    // round trip resolves reads as a swipe that did not work.
    setState(() => _items = [..._items!.where((entry) => entry.id != item.id)]);
    final ok = await NotificationInboxRepository.remove(item.id);
    if (!mounted) return;
    context.read<AppBloc>().add(const RefreshUnreadCountEvent());
    if (!ok) {
      // Put it back and say so. The alternative — leaving it gone locally — is a
      // notification that returns by itself on the next open, which is worse
      // than being told the delete failed.
      await _load();
      if (mounted) _toast(AppLocalizations.of(context).notifInboxDeleteFailed);
    }
  }

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.notifInboxClearTitle),
        content: Text(l10n.notifInboxClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.notifInboxClearConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final previous = _items ?? const <AppNotification>[];
    setState(() => _items = const []);
    final ok = await NotificationInboxRepository.clearAll();
    if (!mounted) return;
    context.read<AppBloc>().add(const RefreshUnreadCountEvent());
    if (!ok) {
      setState(() => _items = previous);
      _toast(l10n.notifInboxDeleteFailed);
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  /// Where a notification leads.
  ///
  /// The same switch as `_NotificationTapListener` in the app shell, because it
  /// is the same question — the only difference is that a tap from the tray
  /// arrives with the app not yet built, and a tap here arrives with a navigator
  /// already on screen. A `splat_ready` therefore pushes the viewer directly;
  /// the others hand the destination to the bloc and pop back to the shell.
  void _open(AppNotification item) {
    switch (item.kind) {
      case 'splat_ready':
        final path = item.data['splat_path'] as String?;
        if (path == null) {
          _toast(AppLocalizations.of(context).notifInboxNothingToOpen);
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SplatViewerScreen(
              storagePath: path,
              title: item.data['scene_title'] as String? ?? item.title,
            ),
          ),
        );
      case 'route_ready':
        final routeId = item.data['route_id'] as String?;
        if (routeId == null) {
          _toast(AppLocalizations.of(context).notifInboxNothingToOpen);
          return;
        }
        context.read<AppBloc>().add(OpenRouteByIdEvent(routeId));
        Navigator.of(context).pop();
      case 'model_ready':
        context.read<AppBloc>().add(const SetScreenEvent('folder'));
        Navigator.of(context).pop();
      default:
        // A kind this build does not route — including one the server learned to
        // send after this app was installed. The row still shows its own copy,
        // which is the part that carries the news.
        _toast(AppLocalizations.of(context).notifInboxNothingToOpen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = _items;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(l10n.notifInboxTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.ink),
        titleTextStyle: const TextStyle(
          color: AppTheme.ink,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        actions: [
          if (items != null && items.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: Text(
                l10n.notifInboxClearAll,
                style: const TextStyle(color: AppTheme.error),
              ),
            ),
        ],
      ),
      body: AppBackdrop(
        child: switch (items) {
          null => const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
          [] => _Empty(),
          _ => RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 100, 20, 40),
                itemCount: items.length,
                separatorBuilder: (_, _) => AppTheme.gap3,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Dismissible(
                    key: ValueKey(item.id),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => _remove(item),
                    background: _DismissBackground(label: l10n.notifInboxDelete),
                    child: _NotificationCard(
                      item: item,
                      onTap: () => _open(item),
                      onDelete: () => _remove(item),
                    ),
                  );
                },
              ),
            ),
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.notifications_none,
              size: 44,
              color: AppTheme.textSecondary,
            ),
            AppTheme.gap4,
            Text(
              l10n.notifInboxEmptyTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.text,
              ),
            ),
            AppTheme.gap2,
            Text(
              l10n.notifInboxEmptyBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The red panel revealed by a swipe. Slid in from the end side so it works
/// unchanged in Arabic, where "swipe left to delete" is swipe *right*.
class _DismissBackground extends StatelessWidget {
  const _DismissBackground({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsetsDirectional.only(end: AppTheme.space5),
      decoration: BoxDecoration(
        color: AppTheme.error,
        borderRadius: AppTheme.brLg,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.delete_outline, color: Colors.white, size: 20),
          AppTheme.gap2,
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  final AppNotification item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// One icon per kind, in the same visual language the Settings switches use —
  /// so the row a traveller taps and the switch that silences it are recognisably
  /// about the same thing.
  static const _icons = {
    'route_ready': Icons.route_outlined,
    'model_ready': Icons.view_in_ar_outlined,
    'mascot_nearby': Icons.pets_outlined,
    'splat_ready': Icons.blur_on,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // A splat is the one kind worth colouring: it is the only notification that
    // is an invitation rather than a status, and it is rare enough that a warm
    // accent in a list of neutral rows is a signal and not decoration.
    final isSplat = item.kind == 'splat_ready';

    return Material(
      color: AppTheme.surface,
      borderRadius: AppTheme.brLg,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppTheme.space4),
          decoration: BoxDecoration(
            borderRadius: AppTheme.brLg,
            border: Border.all(
              color: item.isUnread ? AppTheme.accent : AppTheme.divider,
              width: item.isUnread ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSplat ? AppTheme.secondarySoft : AppTheme.accentSoft,
                  borderRadius: AppTheme.brMd,
                ),
                child: Icon(
                  _icons[item.kind] ?? Icons.notifications_none,
                  size: 20,
                  color: isSplat ? AppTheme.warning : AppTheme.accent,
                ),
              ),
              AppTheme.gap3,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.body,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    AppTheme.gap2,
                    Text(
                      _relative(context, l10n, item.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // A visible delete alongside the swipe: swiping is faster once you
              // know it is there, and nothing on a card announces that it is.
              IconButton(
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: AppTheme.textSecondary,
                  semanticLabel: l10n.notifInboxDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "just now" / "3h ago" / a date, rather than a timestamp.
  ///
  /// Relative for the first week, absolute after: "6d ago" is a useful thing to
  /// know and "43d ago" is not — past a certain age the date is what a traveller
  /// is actually placing the event against. The absolute form comes from
  /// [MaterialLocalizations] rather than a format string of our own, so it lands
  /// in the traveller's own conventions in all three languages.
  String _relative(BuildContext context, AppLocalizations l10n, DateTime at) {
    final elapsed = DateTime.now().difference(at);
    if (elapsed.inMinutes < 1) return l10n.timeJustNow;
    if (elapsed.inHours < 1) return l10n.timeMinutesAgo(elapsed.inMinutes);
    if (elapsed.inDays < 1) return l10n.timeHoursAgo(elapsed.inHours);
    if (elapsed.inDays < 7) return l10n.timeDaysAgo(elapsed.inDays);
    return MaterialLocalizations.of(context).formatShortDate(at);
  }
}
