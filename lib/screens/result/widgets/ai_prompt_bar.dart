import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/app/app_bloc.dart';
import '../../../blocs/app/app_event.dart';
import '../../../theme.dart';
import '../../../widgets/pressable_scale.dart';

/// Sticky single-line AI text input at the bottom of the result screen.
/// Submitting re-generates the route with the new prompt.
class AiPromptBar extends StatefulWidget {
  const AiPromptBar({super.key});

  @override
  State<AiPromptBar> createState() => _AiPromptBarState();
}

class _AiPromptBarState extends State<AiPromptBar> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isNotEmpty) {
      context.read<AppBloc>().add(SetPromptEvent(_controller.text));
      context.read<AppBloc>().add(const GenerateRouteEvent());
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        decoration: BoxDecoration(color: AppTheme.surfaceAlt, borderRadius: AppTheme.brMd),
        child: Stack(
          children: [
            TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'e.g. swap in a coastal stop',
                hintStyle: TextStyle(color: AppTheme.text.withOpacity(0.4), fontSize: 13),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(16, 14, 50, 14),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: PressableScale(
                onTap: _submit,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_upward_rounded, color: AppTheme.onAccent, size: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
