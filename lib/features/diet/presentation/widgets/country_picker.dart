import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/countries.dart';
import '../../../../core/widgets/zivo_choice_row.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../l10n/l10n.dart';

/// "Where do you live?" as a choice, not a text box: a field that shows the
/// picked country (flag + name) and opens a searchable list of every country.
///
/// It replaced a free-text field the user had to type into on every build —
/// a typed "egpyt" steered the generator no better than nothing, and the
/// answer was forgotten the moment the wizard closed. The pick is an ISO
/// code, remembered by the caller.
class CountryPickerField extends StatelessWidget {
  const CountryPickerField({
    required this.selectedCode,
    required this.onChanged,
    super.key,
  });

  final String? selectedCode;

  /// Called with the picked ISO code, or null when the user cleared it.
  final ValueChanged<String?> onChanged;

  Future<void> _open(BuildContext context) async {
    final picked = await showZivoSheet<_CountryPick>(
      context: context,
      builder: (_) => _CountrySheet(selectedCode: selectedCode),
    );
    if (picked != null) onChanged(picked.code);
  }

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final country = countryByCode(selectedCode);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('builder-country-field'),
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 10, 14),
          decoration: BoxDecoration(
            color: TrainColors.glass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: country != null ? TrainColors.green : TrainColors.hairline,
            ),
          ),
          child: Row(
            children: [
              if (country != null) ...[
                Text(country.flag, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
              ] else ...[
                Icon(AppIcons.location, size: 19, color: TrainColors.ink2),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  country?.nameIn(lang) ?? l(context).dietBuilderCountryPick,
                  key: const Key('builder-country-value'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(
                    color: country != null
                        ? TrainColors.ink
                        : TrainColors.ink2,
                    fontSize: 15.5,
                  ),
                ),
              ),
              if (country != null)
                IconButton(
                  key: const Key('builder-country-clear'),
                  tooltip: l(context).dietBuilderCountryClear,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onChanged(null);
                  },
                  icon: Icon(AppIcons.close, size: 16, color: TrainColors.ink3),
                  visualDensity: VisualDensity.compact,
                )
              else
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: Icon(
                    AppIcons.chevronDown,
                    size: 16,
                    color: TrainColors.ink3,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the sheet hands back — wrapped so "closed without picking" (null)
/// is distinguishable from a pick.
class _CountryPick {
  const _CountryPick(this.code);

  final String? code;
}

class _CountrySheet extends StatefulWidget {
  const _CountrySheet({required this.selectedCode});

  final String? selectedCode;

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  final TextEditingController _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final media = MediaQuery.of(context);
    final matches =
        kCountries.where((c) => countryMatches(c, _query.text)).toList()
          ..sort((a, b) => a.nameIn(lang).compareTo(b.nameIn(lang)));
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        // Tall enough to browse, short enough to read as a sheet.
        height: media.size.height * 0.78,
        child: ZivoSheetSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              const Center(child: ZivoSheetHandle()),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
                child: Text(
                  l(context).dietBuilderCountryLabel,
                  style: AppText.rowTitle,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: TextField(
                  key: const Key('country-search'),
                  controller: _query,
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  style: AppText.body.copyWith(color: TrainColors.ink),
                  decoration: InputDecoration(
                    hintText: l(context).dietBuilderCountrySearch,
                    hintStyle: AppText.body.copyWith(color: TrainColors.ink3),
                    prefixIcon: Icon(
                      AppIcons.search,
                      size: 18,
                      color: TrainColors.ink2,
                    ),
                    filled: true,
                    fillColor: TrainColors.glass,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: matches.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l(context).dietBuilderCountryNone,
                          style: AppText.body.copyWith(
                            color: TrainColors.ink2,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          22,
                          4,
                          22,
                          media.padding.bottom + 16,
                        ),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: matches.length,
                        itemBuilder: (context, i) {
                          final c = matches[i];
                          return ZivoChoiceRow(
                            key: Key('country-${c.code}'),
                            label: '${c.flag}   ${c.nameIn(lang)}',
                            selected: c.code == widget.selectedCode,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(context).pop(_CountryPick(c.code));
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
