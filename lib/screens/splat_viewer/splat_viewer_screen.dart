import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/splat_loader.dart';
import '../../theme.dart';
import '../../widgets/compass_spinner.dart';
import '../../widgets/glass_surface.dart';
import '../../widgets/segmented_control.dart';
import 'widgets/splat_view.dart';

/// The scene a traveller's footage helped build, to walk around.
///
/// Opened from the `splat_ready` notification — that is the only way in, because
/// the notification is the only thing that knows a given traveller contributed
/// to a given scene. There is no browsable gallery of splats: the app's
/// relationship to one is "this is what *your* clip became", and a list of
/// everybody else's would be a different feature.
///
/// [storagePath] is a key in the shared `splats` bucket, straight off the
/// notification's `data.splat_path`. It is not validated here beyond what
/// [SplatLoader] does — the row it came from can only have been written by the
/// backend's service_role, so a path in it is as trustworthy as the notification
/// itself.
class SplatViewerScreen extends StatefulWidget {
  const SplatViewerScreen({
    super.key,
    required this.storagePath,
    required this.title,
  });

  final String storagePath;
  final String title;

  @override
  State<SplatViewerScreen> createState() => _SplatViewerScreenState();
}

class _SplatViewerScreenState extends State<SplatViewerScreen> {
  SplatCloud? _cloud;
  String? _error;
  SplatProgress? _progress;
  SplatDetail _detail = SplatDetail.medium;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _progress = null;
    });
    try {
      final cloud = await SplatLoader.load(
        widget.storagePath,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (mounted) setState(() => _cloud = cloud);
    } catch (error) {
      if (!mounted) return;
      // The message is the loader's own — "truncated splat", "bad magic",
      // a storage error — because every one of them tells the traveller
      // something different about whether retrying is worth it.
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cloud = _cloud;

    return Scaffold(
      backgroundColor: AppTheme.deepNavy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (cloud != null)
            SplatView(cloud: cloud, detail: _detail)
          else
            _Loading(progress: _progress, error: _error, onRetry: _load),

          // --- header ---
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.space4),
                child: Row(
                  children: [
                    _RoundButton(
                      icon: Icons.arrow_back,
                      semanticLabel: l10n.actionBack,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    AppTheme.gap3,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            l10n.splatViewerSubtitle,
                            style: const TextStyle(
                              color: AppTheme.sand,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // --- controls ---
          if (cloud != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.space4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.splatViewerHint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      AppTheme.gap3,
                      GlassSurface(
                        tint: GlassTint.dark,
                        padding: const EdgeInsets.all(AppTheme.space3),
                        child: Column(
                          children: [
                            SegmentedControl<SplatDetail>(
                              value: _detail,
                              onChanged: (next) => setState(() => _detail = next),
                              options: [
                                SegmentOption(
                                  value: SplatDetail.low,
                                  label: l10n.splatDetailLow,
                                  semanticLabel: l10n.splatDetailSemantic(
                                    l10n.splatDetailLow,
                                  ),
                                ),
                                SegmentOption(
                                  value: SplatDetail.medium,
                                  label: l10n.splatDetailMedium,
                                  semanticLabel: l10n.splatDetailSemantic(
                                    l10n.splatDetailMedium,
                                  ),
                                ),
                                SegmentOption(
                                  value: SplatDetail.high,
                                  label: l10n.splatDetailHigh,
                                  semanticLabel: l10n.splatDetailSemantic(
                                    l10n.splatDetailHigh,
                                  ),
                                ),
                              ],
                            ),
                            AppTheme.gap2,
                            // The two numbers together are the honest
                            // description of what is on screen: the phone has a
                            // decimation of a much larger training result, and a
                            // traveller comparing it with the dashboard's render
                            // should know why they differ.
                            Text(
                              l10n.splatViewerCounts(
                                cloud.count,
                                cloud.source,
                              ),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Downloading, or the reason it could not be.
class _Loading extends StatelessWidget {
  const _Loading({
    required this.progress,
    required this.error,
    required this.onRetry,
  });

  final SplatProgress? progress;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, color: AppTheme.sand, size: 40),
              AppTheme.gap4,
              Text(
                l10n.splatViewerFailed,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              AppTheme.gap2,
              Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              AppTheme.gap5,
              FilledButton(
                onPressed: onRetry,
                child: Text(l10n.actionTryAgain),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CompassSpinner(),
          AppTheme.gap4,
          Text(
            // Worth naming the size: four megabytes on a mobile connection is a
            // wait, and a spinner with no explanation for it reads as a hang.
            progress == null
                ? l10n.splatViewerOpening
                : l10n.splatViewerDownloading,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      tint: GlassTint.dark,
      borderRadius: AppTheme.brPill,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, semanticLabel: semanticLabel),
      ),
    );
  }
}
