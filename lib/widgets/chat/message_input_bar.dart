import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' as foundation;

class MessageInputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  const MessageInputBar({
    super.key,
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  @override
  State<MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<MessageInputBar> {
  bool _emojiShowing = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _emojiShowing) {
        setState(() => _emojiShowing = false);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleEmoji() {
    if (_emojiShowing) {
      _focusNode.requestFocus();
      setState(() => _emojiShowing = false);
    } else {
      _focusNode.unfocus();
      setState(() => _emojiShowing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Input row ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Emoji toggle button
                IconButton(
                  icon: Icon(
                    _emojiShowing
                        ? Icons.keyboard_rounded
                        : Icons.emoji_emotions_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  splashRadius: 20,
                  onPressed: _toggleEmoji,
                ),

                // Text field
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => widget.onSend(),
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // Send button
                FloatingActionButton.small(
                  onPressed: widget.isSending ? null : widget.onSend,
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  elevation: 0,
                  child: widget.isSending
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                ),
              ],
            ),
          ),

          // ── Emoji picker panel ───────────────────────────────────────
          Offstage(
            offstage: !_emojiShowing,
            child: SizedBox(
              height: 256,
              child: EmojiPicker(
                textEditingController: widget.controller,
                onBackspacePressed: () {
                  final text = widget.controller.text;
                  final selection = widget.controller.selection;
                  if (text.isEmpty) return;

                  final cursorPos = selection.baseOffset;
                  if (cursorPos <= 0) return;

                  final newText = text.characters
                      .toList()
                      .sublist(0, text.characters.length - 1)
                      .join();

                  widget.controller.value = TextEditingValue(
                    text: newText,
                    selection: TextSelection.collapsed(offset: newText.length),
                  );
                },
                config: Config(
                  height: 256,
                  checkPlatformCompatibility: true,
                  emojiTextStyle: const TextStyle(fontSize: 20),
                  emojiViewConfig: EmojiViewConfig(
                    backgroundColor: colorScheme.surface,
                    columns: 8,
                    emojiSizeMax: 28 *
                        (foundation.defaultTargetPlatform ==
                                TargetPlatform.iOS
                            ? 1.2
                            : 1.0),
                  ),
                  categoryViewConfig: CategoryViewConfig(
                    backgroundColor: colorScheme.surfaceContainerLow,
                    indicatorColor: colorScheme.primary,
                    iconColor: colorScheme.onSurfaceVariant,
                    iconColorSelected: colorScheme.primary,
                  ),
                  bottomActionBarConfig: BottomActionBarConfig(
                    backgroundColor: colorScheme.surfaceContainerLow,
                    buttonColor: colorScheme.primary,
                    buttonIconColor: colorScheme.onPrimary,
                  ),
                  searchViewConfig: SearchViewConfig(
                    backgroundColor: colorScheme.surface,
                    buttonIconColor: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
