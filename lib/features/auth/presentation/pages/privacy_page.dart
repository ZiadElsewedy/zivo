import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
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
/// zzivo.com/privacy. Update both together.
const List<PrivacySection> kPrivacySections = [
  PrivacySection(
    'OVERVIEW',
    'ZIVO is a private, personal application for organizing the parts of your '
        'day — moments, workouts, diet, expenses, and more — in one calm place. '
        'This policy explains what ZIVO stores, how it is used, and the choices '
        'you have.',
  ),
  PrivacySection(
    'THE SHORT VERSION',
    '',
    bullets: [
      'Your content is private to your account and never sold or shared for ads.',
      'ZIVO does not use your data or your content to train third-party models.',
      'Backups live in your own Google Drive, under your own control.',
      'You can delete your content at any time, from inside the app.',
    ],
  ),
  PrivacySection(
    'ACCOUNT & AUTHENTICATION',
    'ZIVO uses Firebase Authentication to sign you in, with Apple, Google, or '
        'email/password as sign-in options. Depending on the method you choose, '
        'ZIVO receives basic account details such as your name, email address, '
        'and a unique account identifier. That identifier is what keeps every '
        'piece of your data scoped to your account only.',
  ),
  PrivacySection(
    'EMAIL VERIFICATION CODES',
    'If you sign in with email, ZIVO sends a short verification code to '
        'confirm your address. Codes are hashed before storage, expire within '
        'minutes, and are used for nothing beyond verifying that the address is '
        'yours.',
  ),
  PrivacySection(
    'YOUR CONTENT',
    'Everything you create in ZIVO — moments, workout plans and sessions, '
        'diet plans and entries, expense logs, body-weight entries, and profile '
        'details — is stored in your account so the app can show it back to you '
        'across your devices. It is private to you and not visible to other '
        'users.',
  ),
  PrivacySection(
    'PHOTOS & LOCAL STORAGE',
    'Where a feature lets you attach a photo (such as Moments or your '
        'profile), ZIVO accesses your photo library only when you pick or capture '
        'an image. Media lives first on your device; cloud backup happens only '
        'through the backup target you explicitly choose.',
  ),
  PrivacySection(
    'AI ASSISTANT (“ASK”)',
    'Ask is an opt-in assistant that can answer questions about your own '
        'data — your workouts, meals, and spending. When you send a message, the '
        'relevant context is processed by the model provider solely to answer '
        'you. Conversations are stored privately in your account so history '
        'works across devices, and are never used to train third-party models.',
  ),
  PrivacySection(
    'SPOTIFY',
    'The music feature connects to your own Spotify account when you ask it '
        'to. ZIVO uses Spotify’s official SDK to control playback and read what’s '
        'currently playing. You can disconnect at any time, from Settings.',
  ),
  PrivacySection(
    'ACCOUNT & SECURITY METADATA',
    'To keep your account safe and supportable, ZIVO keeps a small record of '
        'authentication events — when your account was created, when you last '
        'signed in and how, and when verification emails were sent. This '
        'metadata is security bookkeeping: it is never sold, shared, or used for '
        'advertising.',
  ),
  PrivacySection(
    'GOOGLE DRIVE BACKUP',
    'Backup is optional and, if enabled, runs against your own Google Drive '
        '— using Google’s most restrictive drive.file scope, which lets ZIVO see '
        'and manage only the files it created itself. ZIVO never requests broad '
        'access to your Drive, and your files remain under your control there.',
  ),
  PrivacySection(
    'DATA SHARING',
    'ZIVO does not sell or rent personal data. Data is processed only by the '
        'infrastructure needed to run the app — Google Firebase (authentication, '
        'database, functions) — plus the integrations you explicitly enable: '
        'your own Google Drive and your own Spotify account.',
  ),
  PrivacySection(
    'RETENTION & DELETION',
    'Your content is retained until you delete it or delete your account. '
        'Files in your own Google Drive stay there until you remove them, and '
        'Drive access can be revoked at any time — from Settings or from your '
        'Google Account’s third-party access page.',
  ),
  PrivacySection(
    'SECURITY',
    'Access is enforced end-to-end: Firebase Authentication for identity and '
        'Firestore security rules so only your authenticated account can read or '
        'write your data. Verification codes are stored only as salted hashes. '
        'Data is encrypted in transit.',
  ),
  PrivacySection(
    'CHANGES TO THIS POLICY',
    'This policy may be updated as features evolve. The “last updated” date '
        'always reflects the most recent revision.',
  ),
  PrivacySection(
    'CONTACT',
    'Questions about privacy or your data can be sent to '
        'ziadelsewedy1@gmail.com.',
  ),
];

/// The in-app privacy policy — the same document as the public page at
/// zzivo.com/privacy, presented in ZIVO's dashboard language: atmospheric
/// backdrop, editorial title, quiet hairline-divided sections.
///
/// Kept native (rather than a web view) so it reads offline, instantly, and
/// in the app's own typography.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  static const String _lastUpdated = 'August 25, 2026';

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
                              Text('Privacy', style: AppText.greeting),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'How ZIVO handles your data.\nLast updated $_lastUpdated.',
                            style: AppText.body.copyWith(
                              color: TrainColors.ink3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    for (final (i, section) in kPrivacySections.indexed)
                      RiseIn(
                        delay: Duration(milliseconds: 40 + i * 18),
                        child: _SectionBlock(section: section),
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
  const _SectionBlock({required this.section});

  final PrivacySection section;

  @override
  Widget build(BuildContext context) {
    final index = kPrivacySections.indexOf(section);
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
        message: 'Back',
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
