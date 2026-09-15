import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/widgets/contact_marks.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/zivo_toast.dart';
import '../../../../l10n/l10n.dart';

/// "About Me" — who built ZIVO and how to reach them. Opened from the App
/// section of [SettingsPage].
///
/// Dressed in the same pushed-page language as Privacy and Storage & Sync:
/// [TrainScreen] under the Settings wash, the 36px back circle beside a
/// Manrope 800/27 title, then a short intro block and a CONTACT list.
///
/// The two contact rows carry the real brand marks — WhatsApp's green tile,
/// Gmail's four-colour envelope — because a service the user is being pointed
/// to is recognised by its logo before its name. There is no `url_launcher`
/// dependency behind them (every package pays rent, and this one screen does
/// not justify one): tapping a row copies the number or address and confirms
/// with a toast, which works the same whether or not WhatsApp or a mail app is
/// installed.
class AboutMePage extends StatelessWidget {
  const AboutMePage({super.key});

  /// The maker's own contact handles. Proper values, not copy — never
  /// translated, and isolated for RTL so a latin address or number can't
  /// fragment the Arabic around it.
  static const String _whatsappNumber = '+201028203969';
  static const String _whatsappDisplay = '+20 102 820 3969';
  static const String _email = 'Ziadelsewedy1@gmail.com';

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
            TrainPageHeader(title: l(context).aboutTitle),
            const SizedBox(height: 26),
            // What ZIVO is — the page leads with the app itself.
            const RiseIn(child: _AppCard()),
            const SizedBox(height: 24),
            // Then who built it and how to reach them.
            RiseIn(
              delay: const Duration(milliseconds: 90),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child:
                        TrainSectionLabel(l(context).aboutSectionDeveloper),
                  ),
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: TrainColors.sectionFill,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: TrainColors.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _DeveloperHeader(),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: TrainColors.hairline,
                        ),
                        _ContactRow(
                          mark: const WhatsAppMark(size: 26),
                          title: l(context).aboutWhatsapp,
                          value: _whatsappDisplay,
                          copyValue: _whatsappNumber,
                        ),
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 55),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: TrainColors.hairline,
                          ),
                        ),
                        _ContactRow(
                          mark: const GmailMark(size: 26),
                          title: l(context).aboutEmail,
                          value: _email,
                          copyValue: _email,
                          last: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app block: the ZIVO mark, the wordmark, a one-line tagline, and a
/// paragraph on what ZIVO is. The page's subject — what the app is comes
/// before who made it.
class _AppCard extends StatelessWidget {
  const _AppCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TrainColors.raised,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/transparent/zivo-mark-paper-256.png',
                width: 46,
                height: 46,
                filterQuality: FilterQuality.medium,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The wordmark — hardcoded like the brand names on
                    // Settings, not a translated string.
                    Text(
                      'ZIVO',
                      style: AppText.rowTitle.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l(context).aboutAppTagline,
                      style: AppText.meta.copyWith(color: TrainColors.ink3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            l(context).aboutAppBody,
            style: AppText.body.copyWith(height: 1.6, color: TrainColors.ink2),
          ),
        ],
      ),
    );
  }
}

/// The developer's name, role, and the line inviting contact — the head of the
/// Developer section, above the contact rows.
class _DeveloperHeader extends StatelessWidget {
  const _DeveloperHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A proper name — hardcoded, not translated.
          Text(
            'Ziad',
            style: TrainType.ui(
              size: 16,
              weight: FontWeight.w700,
              color: TrainColors.inkPlain,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            l(context).aboutRole,
            style: AppText.meta.copyWith(color: TrainColors.ink3),
          ),
          const SizedBox(height: 10),
          Text(
            l(context).aboutIntro,
            style: AppText.body.copyWith(height: 1.55, color: TrainColors.ink2),
          ),
        ],
      ),
    );
  }
}

/// One contact row: a brand mark, the service name over the handle, and a copy
/// affordance. Tapping copies [copyValue] and confirms with a toast — the row
/// does the same thing whether or not the app it names is installed.
///
/// Built here rather than reusing `SettingsRow` because the value is a phone
/// number or an email that wants its own line at full width instead of being
/// squeezed into the right-aligned value column, where the address would
/// truncate.
class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.mark,
    required this.title,
    required this.value,
    required this.copyValue,
    this.last = false,
  });

  final Widget mark;
  final String title;

  /// What the user reads (a pretty-printed number, the address).
  final String value;

  /// What lands on the clipboard (the raw, dial-ready / send-ready value).
  final String copyValue;
  final bool last;

  Future<void> _copy(BuildContext context) async {
    final strings = l(context);
    await Clipboard.setData(ClipboardData(text: copyValue));
    if (context.mounted) {
      showZivoToast(context, strings.aboutCopied, kind: ToastKind.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            _copy(context);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 15),
            child: Row(
              children: [
                mark,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TrainType.ui(
                          size: 15,
                          weight: FontWeight.w700,
                          color: TrainColors.inkPlain,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isolate(value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TrainType.mono(
                          size: 12,
                          color: TrainColors.ink3,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  AppIcons.duplicate,
                  size: 16,
                  color: TrainColors.inkAt(0.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
