// Copyright 2023, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'game_internals/score.dart';
import 'level_selection/create_party_screen.dart';
import 'level_selection/levels.dart';
import 'main_menu/main_menu_screen.dart';
import 'play_session/play_session_screen.dart';
import 'settings/settings_screen.dart';
import 'style/my_transition.dart';
import 'style/palette.dart';
import 'win_game/win_game_screen.dart';

/// The router describes the game's navigational hierarchy, from the main
/// screen through settings screens all the way to each individual level.
final router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const MainMenuScreen(key: Key('main menu')),
      routes: [
        GoRoute(
          path: 'create-party', // Renamed from /play
          pageBuilder:
              (context, state) => buildMyTransition<void>(
                key: const ValueKey('create_party'),
                color: context.watch<Palette>().backgroundLevelSelection,
                child: const CreatePartyScreen(),
              ),
        ),
        GoRoute(
          path: 'settings',
          builder:
              (context, state) => const SettingsScreen(key: Key('settings')),
        ),
      ],
    ),
  ],
);
