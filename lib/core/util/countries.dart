/// Every country a person might live in — the 193 UN member states, the two
/// observer states, and the few territories people commonly name as "where I
/// live" (Hong Kong, Macau, Taiwan, Puerto Rico, Kosovo) — with its English
/// and Arabic name, for pickers that need the whole world rather than a
/// free-text guess.
///
/// Hand-written rather than a package: a static list of ~200 names doesn't
/// pay a dependency's rent, and the app's two languages are all it needs.
/// Sorted by English name; the picker re-sorts by the display language.
library;

/// One country: its ISO 3166-1 alpha-2 [code] (the stable id to persist —
/// names change, spellings differ) and its [en]/[ar] names.
class Country {
  const Country(this.code, this.en, this.ar);

  final String code;
  final String en;
  final String ar;

  /// The name in [languageCode] — Arabic for `ar`, English otherwise.
  String nameIn(String languageCode) => languageCode == 'ar' ? ar : en;

  /// The flag emoji, built from the code's two regional-indicator letters
  /// (every OS renders these; Kosovo's unofficial `XK` shows as letters on
  /// some, which is still readable).
  String get flag => String.fromCharCodes(
    code.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 0x41),
  );
}

/// All countries, by English name.
const List<Country> kCountries = [
  Country('AF', 'Afghanistan', 'أفغانستان'),
  Country('AL', 'Albania', 'ألبانيا'),
  Country('DZ', 'Algeria', 'الجزائر'),
  Country('AD', 'Andorra', 'أندورا'),
  Country('AO', 'Angola', 'أنغولا'),
  Country('AG', 'Antigua and Barbuda', 'أنتيغوا وباربودا'),
  Country('AR', 'Argentina', 'الأرجنتين'),
  Country('AM', 'Armenia', 'أرمينيا'),
  Country('AU', 'Australia', 'أستراليا'),
  Country('AT', 'Austria', 'النمسا'),
  Country('AZ', 'Azerbaijan', 'أذربيجان'),
  Country('BS', 'Bahamas', 'جزر البهاما'),
  Country('BH', 'Bahrain', 'البحرين'),
  Country('BD', 'Bangladesh', 'بنغلاديش'),
  Country('BB', 'Barbados', 'باربادوس'),
  Country('BY', 'Belarus', 'بيلاروسيا'),
  Country('BE', 'Belgium', 'بلجيكا'),
  Country('BZ', 'Belize', 'بليز'),
  Country('BJ', 'Benin', 'بنين'),
  Country('BT', 'Bhutan', 'بوتان'),
  Country('BO', 'Bolivia', 'بوليفيا'),
  Country('BA', 'Bosnia and Herzegovina', 'البوسنة والهرسك'),
  Country('BW', 'Botswana', 'بوتسوانا'),
  Country('BR', 'Brazil', 'البرازيل'),
  Country('BN', 'Brunei', 'بروناي'),
  Country('BG', 'Bulgaria', 'بلغاريا'),
  Country('BF', 'Burkina Faso', 'بوركينا فاسو'),
  Country('BI', 'Burundi', 'بوروندي'),
  Country('CV', 'Cape Verde', 'الرأس الأخضر'),
  Country('KH', 'Cambodia', 'كمبوديا'),
  Country('CM', 'Cameroon', 'الكاميرون'),
  Country('CA', 'Canada', 'كندا'),
  Country('CF', 'Central African Republic', 'جمهورية أفريقيا الوسطى'),
  Country('TD', 'Chad', 'تشاد'),
  Country('CL', 'Chile', 'تشيلي'),
  Country('CN', 'China', 'الصين'),
  Country('CO', 'Colombia', 'كولومبيا'),
  Country('KM', 'Comoros', 'جزر القمر'),
  Country('CG', 'Congo', 'الكونغو'),
  Country('CD', 'DR Congo', 'الكونغو الديمقراطية'),
  Country('CR', 'Costa Rica', 'كوستاريكا'),
  Country('CI', 'Côte d\'Ivoire', 'ساحل العاج'),
  Country('HR', 'Croatia', 'كرواتيا'),
  Country('CU', 'Cuba', 'كوبا'),
  Country('CY', 'Cyprus', 'قبرص'),
  Country('CZ', 'Czechia', 'التشيك'),
  Country('DK', 'Denmark', 'الدنمارك'),
  Country('DJ', 'Djibouti', 'جيبوتي'),
  Country('DM', 'Dominica', 'دومينيكا'),
  Country('DO', 'Dominican Republic', 'جمهورية الدومينيكان'),
  Country('EC', 'Ecuador', 'الإكوادور'),
  Country('EG', 'Egypt', 'مصر'),
  Country('SV', 'El Salvador', 'السلفادور'),
  Country('GQ', 'Equatorial Guinea', 'غينيا الاستوائية'),
  Country('ER', 'Eritrea', 'إريتريا'),
  Country('EE', 'Estonia', 'إستونيا'),
  Country('SZ', 'Eswatini', 'إسواتيني'),
  Country('ET', 'Ethiopia', 'إثيوبيا'),
  Country('FJ', 'Fiji', 'فيجي'),
  Country('FI', 'Finland', 'فنلندا'),
  Country('FR', 'France', 'فرنسا'),
  Country('GA', 'Gabon', 'الغابون'),
  Country('GM', 'Gambia', 'غامبيا'),
  Country('GE', 'Georgia', 'جورجيا'),
  Country('DE', 'Germany', 'ألمانيا'),
  Country('GH', 'Ghana', 'غانا'),
  Country('GR', 'Greece', 'اليونان'),
  Country('GD', 'Grenada', 'غرينادا'),
  Country('GT', 'Guatemala', 'غواتيمالا'),
  Country('GN', 'Guinea', 'غينيا'),
  Country('GW', 'Guinea-Bissau', 'غينيا بيساو'),
  Country('GY', 'Guyana', 'غيانا'),
  Country('HT', 'Haiti', 'هايتي'),
  Country('HN', 'Honduras', 'هندوراس'),
  Country('HK', 'Hong Kong', 'هونغ كونغ'),
  Country('HU', 'Hungary', 'المجر'),
  Country('IS', 'Iceland', 'آيسلندا'),
  Country('IN', 'India', 'الهند'),
  Country('ID', 'Indonesia', 'إندونيسيا'),
  Country('IR', 'Iran', 'إيران'),
  Country('IQ', 'Iraq', 'العراق'),
  Country('IE', 'Ireland', 'أيرلندا'),
  Country('IL', 'Israel', 'إسرائيل'),
  Country('IT', 'Italy', 'إيطاليا'),
  Country('JM', 'Jamaica', 'جامايكا'),
  Country('JP', 'Japan', 'اليابان'),
  Country('JO', 'Jordan', 'الأردن'),
  Country('KZ', 'Kazakhstan', 'كازاخستان'),
  Country('KE', 'Kenya', 'كينيا'),
  Country('KI', 'Kiribati', 'كيريباتي'),
  Country('XK', 'Kosovo', 'كوسوفو'),
  Country('KW', 'Kuwait', 'الكويت'),
  Country('KG', 'Kyrgyzstan', 'قيرغيزستان'),
  Country('LA', 'Laos', 'لاوس'),
  Country('LV', 'Latvia', 'لاتفيا'),
  Country('LB', 'Lebanon', 'لبنان'),
  Country('LS', 'Lesotho', 'ليسوتو'),
  Country('LR', 'Liberia', 'ليبيريا'),
  Country('LY', 'Libya', 'ليبيا'),
  Country('LI', 'Liechtenstein', 'ليختنشتاين'),
  Country('LT', 'Lithuania', 'ليتوانيا'),
  Country('LU', 'Luxembourg', 'لوكسمبورغ'),
  Country('MO', 'Macau', 'ماكاو'),
  Country('MG', 'Madagascar', 'مدغشقر'),
  Country('MW', 'Malawi', 'مالاوي'),
  Country('MY', 'Malaysia', 'ماليزيا'),
  Country('MV', 'Maldives', 'جزر المالديف'),
  Country('ML', 'Mali', 'مالي'),
  Country('MT', 'Malta', 'مالطا'),
  Country('MH', 'Marshall Islands', 'جزر مارشال'),
  Country('MR', 'Mauritania', 'موريتانيا'),
  Country('MU', 'Mauritius', 'موريشيوس'),
  Country('MX', 'Mexico', 'المكسيك'),
  Country('FM', 'Micronesia', 'ميكرونيزيا'),
  Country('MD', 'Moldova', 'مولدوفا'),
  Country('MC', 'Monaco', 'موناكو'),
  Country('MN', 'Mongolia', 'منغوليا'),
  Country('ME', 'Montenegro', 'الجبل الأسود'),
  Country('MA', 'Morocco', 'المغرب'),
  Country('MZ', 'Mozambique', 'موزمبيق'),
  Country('MM', 'Myanmar', 'ميانمار'),
  Country('NA', 'Namibia', 'ناميبيا'),
  Country('NR', 'Nauru', 'ناورو'),
  Country('NP', 'Nepal', 'نيبال'),
  Country('NL', 'Netherlands', 'هولندا'),
  Country('NZ', 'New Zealand', 'نيوزيلندا'),
  Country('NI', 'Nicaragua', 'نيكاراغوا'),
  Country('NE', 'Niger', 'النيجر'),
  Country('NG', 'Nigeria', 'نيجيريا'),
  Country('KP', 'North Korea', 'كوريا الشمالية'),
  Country('MK', 'North Macedonia', 'مقدونيا الشمالية'),
  Country('NO', 'Norway', 'النرويج'),
  Country('OM', 'Oman', 'عُمان'),
  Country('PK', 'Pakistan', 'باكستان'),
  Country('PW', 'Palau', 'بالاو'),
  Country('PS', 'Palestine', 'فلسطين'),
  Country('PA', 'Panama', 'بنما'),
  Country('PG', 'Papua New Guinea', 'بابوا غينيا الجديدة'),
  Country('PY', 'Paraguay', 'باراغواي'),
  Country('PE', 'Peru', 'بيرو'),
  Country('PH', 'Philippines', 'الفلبين'),
  Country('PL', 'Poland', 'بولندا'),
  Country('PT', 'Portugal', 'البرتغال'),
  Country('PR', 'Puerto Rico', 'بورتوريكو'),
  Country('QA', 'Qatar', 'قطر'),
  Country('RO', 'Romania', 'رومانيا'),
  Country('RU', 'Russia', 'روسيا'),
  Country('RW', 'Rwanda', 'رواندا'),
  Country('KN', 'Saint Kitts and Nevis', 'سانت كيتس ونيفيس'),
  Country('LC', 'Saint Lucia', 'سانت لوسيا'),
  Country('VC', 'Saint Vincent and the Grenadines', 'سانت فنسنت والغرينادين'),
  Country('WS', 'Samoa', 'ساموا'),
  Country('SM', 'San Marino', 'سان مارينو'),
  Country('ST', 'São Tomé and Príncipe', 'ساو تومي وبرينسيب'),
  Country('SA', 'Saudi Arabia', 'السعودية'),
  Country('SN', 'Senegal', 'السنغال'),
  Country('RS', 'Serbia', 'صربيا'),
  Country('SC', 'Seychelles', 'سيشل'),
  Country('SL', 'Sierra Leone', 'سيراليون'),
  Country('SG', 'Singapore', 'سنغافورة'),
  Country('SK', 'Slovakia', 'سلوفاكيا'),
  Country('SI', 'Slovenia', 'سلوفينيا'),
  Country('SB', 'Solomon Islands', 'جزر سليمان'),
  Country('SO', 'Somalia', 'الصومال'),
  Country('ZA', 'South Africa', 'جنوب أفريقيا'),
  Country('KR', 'South Korea', 'كوريا الجنوبية'),
  Country('SS', 'South Sudan', 'جنوب السودان'),
  Country('ES', 'Spain', 'إسبانيا'),
  Country('LK', 'Sri Lanka', 'سريلانكا'),
  Country('SD', 'Sudan', 'السودان'),
  Country('SR', 'Suriname', 'سورينام'),
  Country('SE', 'Sweden', 'السويد'),
  Country('CH', 'Switzerland', 'سويسرا'),
  Country('SY', 'Syria', 'سوريا'),
  Country('TW', 'Taiwan', 'تايوان'),
  Country('TJ', 'Tajikistan', 'طاجيكستان'),
  Country('TZ', 'Tanzania', 'تنزانيا'),
  Country('TH', 'Thailand', 'تايلاند'),
  Country('TL', 'Timor-Leste', 'تيمور الشرقية'),
  Country('TG', 'Togo', 'توغو'),
  Country('TO', 'Tonga', 'تونغا'),
  Country('TT', 'Trinidad and Tobago', 'ترينيداد وتوباغو'),
  Country('TN', 'Tunisia', 'تونس'),
  Country('TR', 'Turkey', 'تركيا'),
  Country('TM', 'Turkmenistan', 'تركمانستان'),
  Country('TV', 'Tuvalu', 'توفالو'),
  Country('UG', 'Uganda', 'أوغندا'),
  Country('UA', 'Ukraine', 'أوكرانيا'),
  Country('AE', 'United Arab Emirates', 'الإمارات'),
  Country('GB', 'United Kingdom', 'المملكة المتحدة'),
  Country('US', 'United States', 'الولايات المتحدة'),
  Country('UY', 'Uruguay', 'الأوروغواي'),
  Country('UZ', 'Uzbekistan', 'أوزبكستان'),
  Country('VU', 'Vanuatu', 'فانواتو'),
  Country('VA', 'Vatican City', 'الفاتيكان'),
  Country('VE', 'Venezuela', 'فنزويلا'),
  Country('VN', 'Vietnam', 'فيتنام'),
  Country('YE', 'Yemen', 'اليمن'),
  Country('ZM', 'Zambia', 'زامبيا'),
  Country('ZW', 'Zimbabwe', 'زيمبابوي'),
];

/// The country with ISO [code] (case-insensitive), or null.
Country? countryByCode(String? code) {
  if (code == null || code.isEmpty) return null;
  final upper = code.toUpperCase();
  for (final c in kCountries) {
    if (c.code == upper) return c;
  }
  return null;
}

/// Case- and accent-insensitive search over both names and the code — "eg",
/// "egy" and "مصر" all find Egypt. An empty [query] matches everything.
bool countryMatches(Country c, String query) {
  final q = _fold(query.trim());
  if (q.isEmpty) return true;
  return _fold(c.en).contains(q) ||
      c.ar.contains(query.trim()) ||
      c.code.toLowerCase() == q;
}

String _fold(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[éèê]'), 'e')
    .replaceAll(RegExp('[ãáâ]'), 'a')
    .replaceAll('í', 'i')
    .replaceAll('ô', 'o');
