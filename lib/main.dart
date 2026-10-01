import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/roam_api.dart';
import 'theme.dart';

void main() => runApp(const MainApp());

class MainApp extends StatelessWidget {
  const MainApp({super.key, this.api});

  final RoamApi? api;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Roam Together',
    theme: buildRoamTheme(),
    home: HomeScreen(api: api),
  );
}
