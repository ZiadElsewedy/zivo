import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/util/date_format.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../l10n/l10n.dart';

/// One section of the privacy policy: an uppercase label, a body paragraph,
/// and optional bullet points. Data-driven so the policy reads as one
/// consistent editorial document, not a pile of hand-styled widgets.
class PrivacySection {
  const PrivacySection(this.label, this.body, {this.bullets = const []});

  final String label;
  final String body;
  final List<String> bullets;
}

/// The policy itself — kept in one place, mirrored by the public version at
/// zzivo.com/privacy. **Update both together**, in both languages: the app and
/// the web page are the same document and must not drift.
///
/// A function rather than a `const` list because the policy is translated, and
/// a translated string needs a [BuildContext] to resolve. The order is the
/// document's order and is meaningful — the divider rhythm and the "short
/// version" summary both depend on it — so sections are built as one list here
/// rather than assembled per-widget.
List<PrivacySection> privacySections(BuildContext context) {
  final t = l(context);
  return [
    PrivacySection(t.privacyOverviewLabel, t.privacyOverviewBody),
    PrivacySection(
      t.privacyShortLabel,
      '',
      bullets: [
        t.privacyShortBullet1,
        t.privacyShortBullet2,
        t.privacyShortBullet3,
        t.privacyShortBullet4,
      ],
    ),
    PrivacySection(t.privacyAccountLabel, t.privacyAccountBody),
    PrivacySection(t.privacyOtpLabel, t.privacyOtpBody),
    PrivacySection(t.privacyContentLabel, t.privacyContentBody),
    PrivacySection(t.privacyPhotosLabel, t.privacyPhotosBody),
    PrivacySection(t.privacyAskLabel, t.privacyAskBody),
    PrivacySection(t.privacySpotifyLabel, t.privacySpotifyBody),
    PrivacySection(t.privacyMetadataLabel, t.privacyMetadataBody),
    PrivacySection(t.privacyDriveLabel, t.privacyDriveBody),
    PrivacySection(t.privacySharingLabel, t.privacySharingBody),
    PrivacySection(t.privacyRetentionLabel, t.privacyRetentionBody),
    PrivacySection(t.privacySecurityLabel, t.privacySecurityBody),
    PrivacySection(t.privacyChangesLabel, t.privacyChangesBody),
    // The address is passed as a placeholder, not written into the sentence:
    // it is a machine identifier, and left inline in an Arabic paragraph the
    // bidi algorithm would break it apart around the "@" and the dot.
    PrivacySection(
      t.privacyContactLabel,
      t.privacyContactBody(isolate(kPrivacyContactEmail)),
    ),
  ];
}

/// Where privacy questions go. A constant, not copy — the same address in
/// every language.
const String kPrivacyContactEmail = 'ziadelsewedy1@gmail.com';

/// The in-app privacy policy — the same document as the public page at
/// zzivo.com/privacy, presented in ZIVO's dashboard language: atmospheric
/// backdrop, editorial title, quiet hairline-divided sections.
///
/// Kept native (rather than a web view) so it reads offline, instantly, and
/// in the app's own typography.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  /// The policy's revision date, as a date rather than a written-out string
  /// so it renders through `intl` in the reader's own locale — "August 25,
  /// 2026" in English, "٢٥ أغسطس ٢٠٢٦" in Arabic — instead of being an English
  /// month name baked into a translated sentence.
  static final DateTime _lastUpdated = DateTime(2026, 8, 25);

  @override
  Widget build(BuildContext context) {
    return TrainScreen(
      tint: TrainColors.settingsTint,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screen,
          12,
          AppSpacing.screen,
          TrainBottomInset.of(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TrainPageHeader(title: l(context).privacyTitle),
            const SizedBox(height: AppSpacing.base),
            RiseIn(
              child: Text(
                l(context).privacyIntro(
                  formatFullDateLong(context, _lastUpdated),
                ),
                style: AppText.body.copyWith(color: TrainColors.ink3),
              ),
            ),
            const SizedBox(height: 28),
            for (final (i, section) in privacySections(context).indexed)
              RiseIn(
                delay: Duration(milliseconds: 40 + i * 18),
                child: _SectionBlock(section: section, index: i),
              ),
          ],
        ),
      ),
    );
  }
}

/// One policy section: uppercase label over body copy, separated from its
/// neighbours by a full-width hairline — the legal-page rhythm of the public
/// site, translated to the app's material.
class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.section, required this.index});

  final PrivacySection section;

  /// Its position in the document — the first section carries no top rule.
  /// Passed in rather than looked up: the sections are rebuilt per locale, so
  /// an `indexOf` against a fresh list would find nothing.
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: index == 0 ? 0 : 18, bottom: 18),
      decoration: index == 0
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: TrainColors.hairline)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.label,
            style: AppText.sectionLabel.copyWith(color: TrainColors.ink),
          ),
          const SizedBox(height: 8),
          if (section.body.isNotEmpty)
            Text(section.body, style: AppText.body.copyWith(height: 1.65)),
          if (section.bullets.isNotEmpty) ...[
            for (final bullet in section.bullets) ...[
              const SizedBox(height: 7),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 7),
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: TrainColors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      bullet,
                      style: AppText.body.copyWith(height: 1.6),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The soft glow behind the header — the settings-family backdrop, tinted to
/// the page's pulse accent.
