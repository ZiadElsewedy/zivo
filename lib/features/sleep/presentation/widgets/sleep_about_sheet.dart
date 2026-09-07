import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../l10n/l10n.dart';
import '../sleep_labels.dart';

/// **What this feature is.** The sheet behind the header's info button.
///
/// It exists because Sleep is the one feature in ZIVO whose behaviour is not
/// guessable from its screen. Everything else does the obvious thing — a set
/// you log is a set you did — while here a tap opens something that records
/// nothing until a second tap closes it, half the numbers arrive from a store
/// the user never sees ZIVO touch, and several figures are deliberately blank.
/// A screen that reads as broken until it is explained needs somewhere to
/// explain itself.
///
/// The last two sections are the ones worth keeping. "Why some figures are
/// blank" turns the gates from a bug into a policy, and "What it will not do"
/// states the one thing the whole feature is built around: ZIVO reports sleep,
/// it does not grade it (`docs/SLEEP_SYSTEM.md` §11).
Future<void> showSleepAboutSheet(BuildContext context) {
  return showZivoSheet<void>(context: context, builder: (_) => const _Sheet());
}

class _Sheet extends StatelessWidget {
  const _Sheet();

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final provider = sleepProviderStoreName(
      context,
      isApple: !kIsWeb && Platform.isIOS,
    );

    return ZivoSheetSurface(
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          // The sheet is content, not a form: it may grow with the text but
          // must not become a full-screen page the user has to scroll out of.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const ZivoSheetHandle(),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(22, AppSpacing.base, 22, 0),
                  children: [
                    Text(strings.sleepAboutTitle, style: AppText.cardTitle),
                    const SizedBox(height: AppSpacing.s),
                    Text(
                      strings.sleepAboutIntro,
                      style: AppText.body.copyWith(color: TrainColors.ink2),
                    ),
                    const SizedBox(height: AppSpacing.l),

                    _Point(
                      icon: AppIcons.sleep,
                      title: strings.sleepAboutSessionTitle,
                      body: strings.sleepAboutSessionBody,
                    ),
                    _Point(
                      icon: AppIcons.sleepSync,
                      title: strings.sleepAboutTrackedTitle,
                      body: strings.sleepAboutTrackedBody(provider),
                    ),
                    _Point(
                      icon: AppIcons.sleepSources,
                      title: strings.sleepAboutSourcesTitle,
                      body: strings.sleepAboutSourcesBody,
                    ),
                    _Point(
                      icon: AppIcons.sleepWeek,
                      title: strings.sleepAboutWeekTitle,
                      body: strings.sleepAboutWeekBody,
                    ),
                    _Point(
                      icon: AppIcons.sleepNoGrade,
                      title: strings.sleepAboutLimitsTitle,
                      body: strings.sleepAboutLimitsBody,
                      last: true,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, AppSpacing.base, 22, 28),
                child: SizedBox(
                  width: double.infinity,
                  child: TrainPrimaryButton(
                    label: strings.sleepAboutDone,
                    color: TrainColors.sleepAccent,
                    labelColor: TrainColors.sleepOnAccent,
                    height: 54,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One explained point: a tinted glyph in the leading column, the claim as a
/// heading, the detail beneath it.
class _Point extends StatelessWidget {
  const _Point({
    required this.icon,
    required this.title,
    required this.body,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: TrainColors.sleepWash,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 15, color: TrainColors.sleepGlyph),
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.rowTitle),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: AppText.body.copyWith(color: TrainColors.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
