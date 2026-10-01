import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/roam_api.dart';
import 'services/supabase_roam_api.dart';
import 'theme.dart';

void main() => runApp(const MainApp());

/// Owns the single RoamApi instance for the app's lifetime, so sign-in state
/// (the bearer token / Supabase session) survives navigation between screens.
class MainApp extends StatefulWidget {
  const MainApp({super.key, this.api});

  final RoamApi? api;

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late final RoamApi _api;
  var _ownsApi = false;

  @override
  void initState() {
    super.initState();
    if (widget.api != null) {
      _api = widget.api!;
    } else {
      _api = const bool.fromEnvironment('USE_LOCAL_BACKEND')
          ? RoamApi()
          : SupabaseRoamApi();
      _ownsApi = true;
    }
  }

  @override
  void dispose() {
    if (_ownsApi) _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Roam Together',
    theme: buildRoamTheme(),
    home: HomeScreen(api: _api),
  );
}
