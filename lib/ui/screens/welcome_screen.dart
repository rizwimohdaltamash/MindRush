import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/game_mode.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/wiggle_button.dart';

/// First launch: pick a name and an avatar.
///
/// Deliberately not a sign-in wall. Everything in MindRush works offline, and
/// gating it behind a Google account would mean no wifi equals a dead screen --
/// on top of spending the first thirty seconds of a demo on an account picker.
/// A name is all the app actually needs, it takes five seconds, and Google
/// sign-in can be linked to the same account later without losing a thing.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final TextEditingController _name = TextEditingController();
  int _avatarId = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canStart => _name.text.trim().isNotEmpty && !_saving;

  Future<void> _start() async {
    if (!_canStart) return;
    setState(() => _saving = true);
    HapticFeedback.selectionClick();
    final notifier = ref.read(profileProvider.notifier);
    await notifier.setAvatar(_avatarId);
    // Setting the name last is what ends onboarding, so it must not happen
    // until the avatar is safely stored.
    await notifier.setName(_name.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final category in Category.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(category.icon, color: category.color, size: 30),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'MindRush',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: AppColors.text,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Sixty-second duels of maths, memory and logic',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            const SizedBox(height: 44),
            Text(
              'WHAT SHOULD WE CALL YOU?',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 16,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _start(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Your name',
                counterText: '',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'PICK AN AVATAR',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var id = 0; id < 12; id++)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _avatarId = id);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: id == _avatarId
                              ? AvatarBadge.colorFor(id)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: AvatarBadge(
                        avatarId: id,
                        // Shows the real initial as soon as there is one.
                        name: _name.text.trim().isEmpty ? '?' : _name.text,
                        size: 46,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: Wiggle(
                onPressed: _canStart ? _start : null,
                builder: (context, press) => FilledButton(
                  onPressed: press,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.math,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: AppColors.surfaceHigh,
                    disabledForegroundColor: AppColors.textMuted,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Start playing',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'No account needed. You can change this any time.',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
