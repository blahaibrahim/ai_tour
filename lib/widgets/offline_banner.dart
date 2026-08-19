import 'package:flutter/material.dart';

import '../theme.dart';
import '../l10n/app_localizations.dart';

/// A slim, animated banner indicating offline status during a tour.
///
/// Shows "Offline — your progress is saved" in an amber tint when offline,
/// and briefly transitions to "Back online — syncing…" in green on reconnect
/// before hiding. Designed to sit at the top of the overview screen's
/// ListView.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({
    super.key,
    required this.isOffline,
    this.pendingSyncCount = 0,
  });

  final bool isOffline;
  final int pendingSyncCount;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  /// Tracks whether we were previously offline so we can show the "syncing"
  /// transition on reconnect.
  bool _showingSyncMessage = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    if (widget.isOffline) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(OfflineBanner oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isOffline && !oldWidget.isOffline) {
      // Going offline — slide in.
      _showingSyncMessage = false;
      _controller.forward();
    } else if (!widget.isOffline && oldWidget.isOffline) {
      // Coming back online — show "syncing" briefly, then hide.
      _showingSyncMessage = true;
      setState(() {});
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !widget.isOffline) {
          _controller.reverse();
          // Clean up the sync message state after animation completes.
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted) setState(() => _showingSyncMessage = false);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppTheme.space3),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space4,
            vertical: AppTheme.space3,
          ),
          decoration: BoxDecoration(
            color: _showingSyncMessage
                ? AppTheme.success.withValues(alpha: 0.15)
                : AppTheme.warningSoft,
            borderRadius: AppTheme.brMd,
            border: Border.all(
              color: _showingSyncMessage
                  ? AppTheme.success.withValues(alpha: 0.4)
                  : AppTheme.warning.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _showingSyncMessage
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                size: 18,
                color: _showingSyncMessage
                    ? AppTheme.success
                    : AppTheme.warning,
              ),
              const SizedBox(width: AppTheme.space2),
              Expanded(
                child: Text(
                  _showingSyncMessage
                      ? AppLocalizations.of(context).offlineBackOnline
                      : _buildOfflineMessage(AppLocalizations.of(context)),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _showingSyncMessage
                        ? AppTheme.success
                        : AppTheme.warning,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildOfflineMessage(AppLocalizations l10n) {
    if (widget.pendingSyncCount > 0) {
      return l10n.offlinePendingSync(widget.pendingSyncCount);
    }
    return l10n.offlineProgressSaved;
  }
}
