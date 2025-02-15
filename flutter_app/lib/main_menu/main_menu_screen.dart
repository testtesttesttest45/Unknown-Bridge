import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../audio/audio_controller.dart';
import '../audio/sounds.dart';
import '../settings/settings.dart';
import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/responsive_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  MainMenuScreenState createState() => MainMenuScreenState();
}

class MainMenuScreenState extends State<MainMenuScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkForPlayerName();  // Ensure settings are loaded first
    });
  }

    Future<void> _checkForPlayerName() async {
    final settingsController = context.read<SettingsController>();
    await settingsController.loadSettings();  // Load settings first

    if (settingsController.playerName.value.isEmpty) { // Ensure name is truly empty
      _showNameDialog();
    }
  }


  void _showNameDialog() {
    final settingsController = context.read<SettingsController>();
    TextEditingController nameController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("What is your name?"),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              hintText: "Enter your name",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  settingsController.setPlayerName(nameController.text);
                  Navigator.of(context).pop();
                }
              },
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();
    final audioController = context.watch<AudioController>();

    return Scaffold(
      backgroundColor: palette.backgroundMain,
      body: ResponsiveScreen(
        squarishMainArea: Center(
          child: Transform.rotate(
            angle: -0.1,
            child: const Text(
              'Unknown Bridge',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Permanent Marker',
                fontSize: 55,
                height: 1,
              ),
            ),
          ),
        ),
        rectangularMenuArea: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MyButton(
              onPressed: () {
                audioController.playSfx(SfxType.buttonTap);
                GoRouter.of(context).go('/play');
              },
              child: const Text('Play'),
            ),
            _gap,
            MyButton(
              onPressed: () => GoRouter.of(context).push('/settings'),
              child: const Text('Settings'),
            ),
            _gap,
            const Text('Music by Mr Smith'),
            _gap,
          ],
        ),
      ),
    );
  }

  static const _gap = SizedBox(height: 10);
}
