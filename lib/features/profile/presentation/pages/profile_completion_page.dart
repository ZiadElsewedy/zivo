import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/date_format.dart';
import '../../../../core/widgets/back_chip.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/domain/auth_user.dart';
import '../../../auth/presentation/widgets/auth_action_button.dart';
import '../../../auth/presentation/widgets/auth_backdrop.dart';
import '../../../auth/presentation/widgets/auth_header.dart';
import '../../../auth/presentation/widgets/auth_text_field.dart';
import '../widgets/dob_picker_sheet.dart';

/// Collects the missing Name / Date of birth for a signed-in user with an
/// incomplete profile.
///
/// Success is handled by [AuthGate]: a successful save flips the profile
/// stream to a complete `UserProfile`, which swaps this page out for the app
/// shell — so this page only owns loading and error presentation and never
/// navigates itself.
///
/// ## Why it is dressed like the auth screens
///
/// This is the **last step of signing up**, and it used to be the one step
/// that looked like a different product: a bare Material `AppBar` over flat
/// black instead of the ember [AuthBackdrop], a hand-rolled title instead of
/// [AuthHeader], and two fields it wrote itself — 20px corners and a 1.4px
/// stroke — instead of the [AuthTextField] the user had just finished typing
/// into on the previous screen. Same flow, same chrome now.
class ProfileCompletionPage extends StatefulWidget {
  const ProfileCompletionPage({
    required this.user,
    this.suggestedName,
    super.key,
  });

  final AuthUser user;
  final String? suggestedName;

  @override
  State<ProfileCompletionPage> createState() => _ProfileCompletionPageState();
}

class _ProfileCompletionPageState extends State<ProfileCompletionPage> {
  late final TextEditingController _name = TextEditingController(
    text: _initialName,
  );

  DateTime? _dob;
  bool _saving = false;
  String? _error;

  /// Prefill from [ProfileCompletionPage.suggestedName] when it carries a
  /// real value; the gate may pass an empty string for a blank-name profile,
  /// which counts as "no suggestion" and falls back to the auth display name.
  String get _initialName {
    final suggested = widget.suggestedName?.trim();
    if (suggested != null && suggested.isNotEmpty) return suggested;
    return widget.user.displayName ?? '';
  }

  bool get _canSubmit => _name.text.trim().isNotEmpty && _dob != null;

  @override
  void initState() {
    super.initState();
    // Rebuild live so the submit button's enabled state tracks the field.
    _name.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _name.dispose();
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  Future<void> _pickDob() async {
    if (_saving) return;
    // The shared wheel enforces the same 13+ / 120-year bounds this screen
    // used to set on the stock `showDatePicker`, so onboarding and profile-edit
    // present the identical ZIVO picker.
    final picked = await showDobPicker(context, initial: _dob);
    if (picked == null) return;
    setState(() {
      _dob = picked;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_saving || !_canSubmit) return;
    // Both read before the await — a BuildContext must not cross an async
    // gap, and AppLocalizations is a plain value so a local copy is safe.
    final profiles = AppScope.of(context).profiles;
    final strings = l(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await profiles.saveProfile(
        uid: widget.user.uid,
        name: _name.text.trim(),
        dateOfBirth: _dob!,
      );
      // The gate advances on the refreshed profile stream; nothing to do here.
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = strings.profileSaveFailed;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
  }

  Future<void> _useAnotherAccount() async {
    await AppScope.of(context).auth.signOut();
    // The gate returns to the auth screen on Unauthenticated.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TrainColors.base,
      body: AuthBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  6,
                  AppSpacing.screen,
                  0,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  // Leaving here means signing out, not going back a page — so
                  // the chip keeps the account wording it always had.
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: BackChip(
                      enabled: !_saving,
                      onTap: _useAnotherAccount,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            AppSpacing.screen,
            AppSpacing.screen,
            AppSpacing.l,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RiseIn(
                child: AuthHeader(
                  title: l(context).profileCompleteTitle,
                  aside: l(context).profileCompleteSubtitle,
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              RiseIn(
                delay: const Duration(milliseconds: 70),
                child: Column(
                  children: [
                    AuthTextField(
                      controller: _name,
                      hint: l(context).profileName,
                      icon: Icons.person_outline_rounded,
                      enabled: !_saving,
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 10),
                    _DobField(date: _dob, enabled: !_saving, onTap: _pickDob),
                  ],
                ),
              ),
              // Reserve a line for the error so nothing jumps.
              SizedBox(
                height: 28,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _error == null ? 0 : 1,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error ?? '',
                      style: AppText.meta.copyWith(color: TrainColors.ember),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              RiseIn(
                delay: const Duration(milliseconds: 120),
                child: AuthActionButton(
                  label: l(context).actionContinue,
                  loading: _saving,
                  enabled: !_saving && _canSubmit,
                  onTap: _submit,
                ),
              ),
            ],
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

/// The date-of-birth row, built to match [AuthTextField] exactly: same 54px
/// height, same border weights, same ember focus edge, same label behaviour —
/// the label rises to a tracked caption once a date is chosen, so a filled row
/// still says what it holds.
///
/// It cannot *be* an [AuthTextField] (it opens a picker and holds no editable
/// text), which is precisely why it has to be built to the same numbers rather
/// than to its own: the two sit one above the other, and a 20px-cornered box
/// beside a 20px-cornered box with different padding is the kind of mismatch
/// you feel before you can name it.
class _DobField extends StatelessWidget {
  const _DobField({
    required this.date,
    required this.enabled,
    required this.onTap,
  });

  final DateTime? date;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasDate = date != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: TrainColors.raised,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: TrainColors.hairlineStrong,
                width: 1.4,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.cake_outlined,
                  size: 18,
                  color: TrainColors.ink3,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: hasDate
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l(context).profileDateOfBirth,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.sectionLabel.copyWith(
                                fontSize: 10.5,
                                letterSpacing: 0.9,
                                color: TrainColors.ink3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatDayMonthYear(context, date!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.rowTitle.copyWith(fontSize: 15),
                            ),
                          ],
                        )
                      : Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            l(context).profileDateOfBirth,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.rowTitle.copyWith(
                              color: TrainColors.ink3,
                            ),
                          ),
                        ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Color(0x4DF4F4F0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
