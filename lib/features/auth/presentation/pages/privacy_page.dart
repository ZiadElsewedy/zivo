import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/util/date_format.dart';
import '../../../../l10n/l10n.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/theme/train_tokens.dart';

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
    return Scaffold(
      backgroundColor: TrainColors.base,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.1),
            radius: 1.15,
            colors: [Color(0xFF231B14), TrainColors.base, Color(0xFF0E0B08)],
            stops: [0.0, 0.52, 1.0],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -60,
              right: -70,
              child: _Glow(color: TrainColors.green, size: 200),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 44),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RiseIn(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _BackButton(),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              const Icon(
                                AppIcons.privacy,
                                size: 26,
                                color: TrainColors.green,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                l(context).privacyTitle,
                                style: AppText.greeting,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l(context).privacyIntro(
                              formatFullDateLong(context, _lastUpdated),
                            ),
                            style: AppText.body.copyWith(
                              color: TrainColors.ink3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    for (final (i, section)
                        in privacySections(context).indexed)
                      RiseIn(
                        delay: Duration(milliseconds: 40 + i * 18),
                        child: _SectionBlock(section: section, index: i),
                      ),
                  ],
                ),
              ),
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
          : const BoxDecoration(
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
                    decoration: const BoxDecoration(
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
class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.14),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

/// The same 38px back chip as Settings — pushed pages share one affordance.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Tooltip(
        message: l(context).actionBack,
        child: InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          customBorder: const CircleBorder(),
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: TrainColors.raisedStrong,
              shape: BoxShape.circle,
              border: Border.all(color: TrainColors.hairlineStrong),
            ),
            child: const Icon(AppIcons.back, size: 18, color: TrainColors.ink2),
          ),
        ),
      ),
    );
  }
}
