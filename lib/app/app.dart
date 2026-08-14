import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/shell/presentation/home_shell.dart';

/// The ZIVO application root.
class ZivoApp extends StatelessWidget {
  const ZivoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZIVO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const HomeShell(),
    );
  }
}
