import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/auth_user.dart';
import '../widgets/auth_action_button.dart';
import '../widgets/dob_picker_sheet.dart';

/// Collects the missing Name / Date of birth for a signed-in user with an
/// incomplete profile.
///
/// Success is handled by [AuthGate]: a successful save flips the profile
/// stream to a complete `UserProfile`, which swaps this page out for the app
/// shell — so this page only owns loading and error presentation and never
/// navigates itself.
class ProfileCompletionPage extends StatefulWidget {
  const ProfileCompletionPage({required this.user, this.suggestedName, super.key});

  final AuthUser user;
  final String? suggestedName;

  @override
  State<ProfileCompletionPage> createState() => _ProfileCompletionPageState();
}

class _ProfileCompletionPageState extends State<ProfileCompletionPage> {
  late final TextEditingController _name = TextEditingController(text: _initialName);

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
    final profiles = AppScope.of(context).profiles; // read before await
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
        _error = "We couldn't save your profile. Please try again.";
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
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink),
          tooltip: 'Use another account',
          onPressed: _saving ? null : _useAnotherAccount,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              RiseIn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Complete your profile',
                        style: AppText.greeting.copyWith(fontSize: 28)),
                    const SizedBox(height: 10),
                    Text(
                      'A couple of details to personalise ZIVO.',
                      style: AppText.aside,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              RiseIn(
                delay: const Duration(milliseconds: 70),
                child: Column(
                  children: [
                    _NameField(controller: _name, enabled: !_saving),
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
                      style: AppText.meta.copyWith(color: AppColors.flareText),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              RiseIn(
                delay: const Duration(milliseconds: 120),
                child: AuthActionButton(
                  label: 'Continue',
                  loading: _saving,
                  enabled: !_saving && _canSubmit,
                  onTap: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A ZIVO-styled Name text field, matching `email_auth_form.dart`'s `_Field`
/// (white card, hairline border, ember focus).
class _NameField extends StatelessWidget {
  const _NameField({required this.controller, required this.enabled});

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autocorrect: false,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      style: AppText.rowTitle,
      cursorColor: AppColors.ember,
      decoration: InputDecoration(
        hintText: 'Name',
        hintStyle: AppText.rowTitle.copyWith(color: AppColors.ink3),
        prefixIcon: const Icon(Icons.person_outline_rounded, size: 20, color: AppColors.ink3),
        filled: true,
        fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: const BorderSide(color: AppColors.hairline2, width: 1.4),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: const BorderSide(color: AppColors.hairline2, width: 1.4),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: const BorderSide(color: AppColors.ember, width: 1.6),
        ),
      ),
    );
  }
}

/// A tappable, `_NameField`-matching row that opens [showDatePicker] and
/// displays the selected date (or a placeholder) — no `intl` dependency, so
/// the date is formatted with a tiny local month-name lookup.
class _DobField extends StatelessWidget {
  const _DobField({required this.date, required this.enabled, required this.onTap});

  final DateTime? date;
  final bool enabled;
  final VoidCallback onTap;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _format(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final hasDate = date != null;
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline2, width: 1.4),
          ),
          child: Row(
            children: [
              const Icon(Icons.cake_outlined, size: 20, color: AppColors.ink3),
              const SizedBox(width: 12),
              Text(
                hasDate ? _format(date!) : 'Date of birth',
                style: AppText.rowTitle.copyWith(
                  color: hasDate ? AppColors.ink : AppColors.ink3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
