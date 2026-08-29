import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_icons.dart';
import '../../domain/expense_category.dart';

/// Maps a category's [CategoryIcon] to its stroked glyph from the app's one
/// icon vocabulary (`AppIcons`) — the icon counterpart to `hueColor()`.
///
/// Routed through `AppIcons` rather than importing Lucide here on purpose:
/// that file is the single place the app names its icon set, and nothing else
/// in `lib/` imports the icon package directly.
IconData categoryIcon(CategoryIcon icon) => switch (icon) {
  CategoryIcon.food => AppIcons.catFood,
  CategoryIcon.coffee => AppIcons.catCoffee,
  CategoryIcon.transport => AppIcons.catTransport,
  CategoryIcon.groceries => AppIcons.catGroceries,
  CategoryIcon.shopping => AppIcons.catShopping,
  CategoryIcon.entertainment => AppIcons.catEntertainment,
  CategoryIcon.home => AppIcons.catHome,
  CategoryIcon.health => AppIcons.catHealth,
  CategoryIcon.education => AppIcons.catEducation,
  CategoryIcon.travel => AppIcons.catTravel,
  CategoryIcon.pets => AppIcons.catPets,
  CategoryIcon.gifts => AppIcons.catGifts,
  CategoryIcon.utilities => AppIcons.catUtilities,
  CategoryIcon.phone => AppIcons.catPhone,
  CategoryIcon.games => AppIcons.catGames,
  CategoryIcon.drinks => AppIcons.catDrinks,
  CategoryIcon.car => AppIcons.catCar,
  CategoryIcon.fitness => AppIcons.catFitness,
  CategoryIcon.books => AppIcons.catBooks,
  CategoryIcon.grooming => AppIcons.catGrooming,
  CategoryIcon.music => AppIcons.catMusic,
  CategoryIcon.parking => AppIcons.catParking,
  CategoryIcon.bills => AppIcons.catBills,
  CategoryIcon.personalCare => AppIcons.catPersonalCare,
  CategoryIcon.other => AppIcons.catOther,
};

/// The icons offered when creating a category, in picker order.
///
/// [CategoryIcon.other] is deliberately absent: it is the neutral fallback for
/// the "Other" built-in and for unrecognised stored values, not something a
/// user picks on purpose.
const kPickableCategoryIcons = <CategoryIcon>[
  CategoryIcon.food,
  CategoryIcon.coffee,
  CategoryIcon.transport,
  CategoryIcon.groceries,
  CategoryIcon.shopping,
  CategoryIcon.entertainment,
  CategoryIcon.home,
  CategoryIcon.health,
  CategoryIcon.education,
  CategoryIcon.travel,
  CategoryIcon.pets,
  CategoryIcon.gifts,
  CategoryIcon.utilities,
  CategoryIcon.phone,
  CategoryIcon.games,
  CategoryIcon.drinks,
  CategoryIcon.car,
  CategoryIcon.fitness,
  CategoryIcon.books,
  CategoryIcon.grooming,
  CategoryIcon.music,
  CategoryIcon.parking,
  CategoryIcon.bills,
  CategoryIcon.personalCare,
];
