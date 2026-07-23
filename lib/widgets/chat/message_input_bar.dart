import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:image_picker/image_picker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class MessageInputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;
  final Function({
    required String filePath,
    required String fileName,
    required int fileSize,
    required String type,
    String? caption,
  })?
  onSendMedia;
  final Future<void> Function({
    required String filePath,
    required String fileName,
    required int fileSize,
    required int durationSeconds,
  })?
  onSendVoice;

  const MessageInputBar({
    super.key,
    required this.controller,
    required this.isSending,
    required this.onSend,
    this.onSendMedia,
    this.onSendVoice,
  });

  @override
  State<MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<MessageInputBar> {
  bool _emojiShowing = false;
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _recordingTimer;
  bool _isRecording = false;
  bool _isRecordingPaused = false;
  bool _hasText = false;
  int _recordingSeconds = 0;
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _emojiShowing) {
        setState(() => _emojiShowing = false);
      }
    });
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _recordingTimer?.cancel();
    _recorder.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (_hasText != hasText && mounted) setState(() => _hasText = hasText);
  }

  Future<void> _startVoiceRecording() async {
    if (widget.onSendVoice == null || widget.isSending) return;
    try {
      final granted = await _checkPermission(Permission.microphone);
      if (!granted) return;
      if (!await _recorder.hasPermission()) {
        _showErrorSnackBar(
          'Microphone permission is required to record a voice message.',
        );
        return;
      }
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recordingPath = path;
        _recordingSeconds = 0;
        _isRecording = true;
        _isRecordingPaused = false;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && !_isRecordingPaused) {
          setState(() => _recordingSeconds++);
        }
      });
    } catch (e) {
      _showErrorSnackBar('Could not start voice recording: $e');
    }
  }

  Future<void> _toggleRecordingPause() async {
    try {
      if (_isRecordingPaused) {
        await _recorder.resume();
      } else {
        await _recorder.pause();
      }
      if (mounted) setState(() => _isRecordingPaused = !_isRecordingPaused);
    } catch (e) {
      _showErrorSnackBar('Could not update recording: $e');
    }
  }

  Future<void> _discardVoiceRecording() async {
    final path = await _recorder.stop() ?? _recordingPath;
    _recordingTimer?.cancel();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    if (mounted) {
      setState(() {
        _isRecording = false;
        _isRecordingPaused = false;
        _recordingPath = null;
        _recordingSeconds = 0;
      });
    }
  }

  Future<void> _sendVoiceRecording() async {
    if (widget.onSendVoice == null) return;
    try {
      final path = await _recorder.stop() ?? _recordingPath;
      _recordingTimer?.cancel();
      if (path == null || _recordingSeconds == 0) {
        if (path != null) {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
        if (mounted) {
          setState(() {
            _isRecording = false;
            _isRecordingPaused = false;
            _recordingPath = null;
            _recordingSeconds = 0;
          });
        }
        return;
      }
      final file = File(path);
      if (!await file.exists())
        throw Exception('Recording file is unavailable.');
      final size = await file.length();
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isRecordingPaused = false;
          _recordingPath = null;
        });
      }
      await widget.onSendVoice!(
        filePath: path,
        fileName: 'Voice message.m4a',
        fileSize: size,
        durationSeconds: _recordingSeconds,
      );
      if (mounted) setState(() => _recordingSeconds = 0);
    } catch (e) {
      _showErrorSnackBar('Could not send voice message: $e');
    }
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

  Future<bool> _checkPermission(Permission permission) async {
    final status = await permission.status;
    if (status.isGranted || status.isLimited) return true;
    final result = await permission.request();
    if (result.isGranted || result.isLimited) return true;
    if (result.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Permission Required'),
            content: const Text(
              'Please grant permission in app settings to use this feature.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
      return false;
    }
    return false;
  }

  void _showAttachmentMenu() {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _AttachmentItem(
                  icon: Icons.insert_drive_file,
                  label: 'Document',
                  color: Colors.indigo,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickDocument();
                  },
                ),
                _AttachmentItem(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  color: Colors.pink,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickCamera();
                  },
                ),
                _AttachmentItem(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  color: Colors.purple,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickGallery();
                  },
                ),
                _AttachmentItem(
                  icon: Icons.headset,
                  label: 'Audio',
                  color: Colors.orange,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAudio();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = result.files.single;
        _confirmAndSendMedia(
          filePath: file.path!,
          fileName: file.name,
          fileSize: file.size,
          type: 'document',
        );
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick document: $e');
    }
  }

  Future<void> _pickCamera() async {
    final granted = await _checkPermission(Permission.camera);
    if (!granted) return;
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (photo != null) {
        final file = File(photo.path);
        final length = await file.length();
        _confirmAndSendMedia(
          filePath: photo.path,
          fileName: photo.name,
          fileSize: length,
          type: 'image',
        );
      }
    } catch (e) {
      _showErrorSnackBar('Failed to capture photo: $e');
    }
  }

  Future<void> _pickGallery() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.media,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = result.files.single;
        final ext = file.name.split('.').last.toLowerCase();
        final isVideo = [
          'mp4',
          'mov',
          'ts',
          'mkv',
          'avi',
          'webm',
        ].contains(ext);

        _confirmAndSendMedia(
          filePath: file.path!,
          fileName: file.name,
          fileSize: file.size,
          type: isVideo ? 'video' : 'image',
        );
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick media: $e');
    }
  }

  Future<void> _pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = result.files.single;
        _confirmAndSendMedia(
          filePath: file.path!,
          fileName: file.name,
          fileSize: file.size,
          type: 'audio',
        );
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick audio: $e');
    }
  }

  void _confirmAndSendMedia({
    required String filePath,
    required String fileName,
    required int fileSize,
    required String type,
  }) {
    if (widget.onSendMedia == null) return;

    final captionCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send ${type[0].toUpperCase()}${type.substring(1)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getIconForType(type),
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    fileName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _formatFileSize(fileSize),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: captionCtrl,
              decoration: const InputDecoration(
                labelText: 'Add a caption (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onSendMedia!(
                filePath: filePath,
                fileName: fileName,
                fileSize: fileSize,
                type: type,
                caption: captionCtrl.text.trim(),
              );
            },
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Send'),
          ),
        ],
      ),
    );
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.videocam;
      case 'audio':
        return Icons.audiotrack;
      case 'document':
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
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
            child: _isRecording
                ? _RecordingBar(
                    seconds: _recordingSeconds,
                    isPaused: _isRecordingPaused,
                    onDelete: _discardVoiceRecording,
                    onTogglePause: _toggleRecordingPause,
                    onSend: widget.isSending ? null : _sendVoiceRecording,
                    isSending: widget.isSending,
                    colorScheme: colorScheme,
                  )
                : Row(
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

                      // Attachment button
                      IconButton(
                        icon: Icon(
                          Icons.attach_file_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        splashRadius: 20,
                        onPressed: widget.isSending
                            ? null
                            : _showAttachmentMenu,
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

                      // Send text, or start a voice message when the draft is empty.
                      FloatingActionButton.small(
                        heroTag: 'sendOrRecord',
                        onPressed: widget.isSending
                            ? null
                            : (_hasText ? widget.onSend : _startVoiceRecording),
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
                            : Icon(
                                _hasText
                                    ? Icons.send_rounded
                                    : Icons.mic_rounded,
                                size: 20,
                              ),
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
                    emojiSizeMax:
                        28 *
                        (foundation.defaultTargetPlatform == TargetPlatform.iOS
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

class _AttachmentItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachmentItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: color,
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// WhatsApp-style recording bar with pulsing mic and animated waveform.
class _RecordingBar extends StatefulWidget {
  final int seconds;
  final bool isPaused;
  final VoidCallback onDelete;
  final VoidCallback onTogglePause;
  final VoidCallback? onSend;
  final bool isSending;
  final ColorScheme colorScheme;

  const _RecordingBar({
    required this.seconds,
    required this.isPaused,
    required this.onDelete,
    required this.onTogglePause,
    required this.onSend,
    required this.isSending,
    required this.colorScheme,
  });

  @override
  State<_RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<_RecordingBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_RecordingBar old) {
    super.didUpdateWidget(old);
    if (widget.isPaused && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
    } else if (!widget.isPaused && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  String _fmt(int s) {
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  static const List<double> _wave = [
    0.3, 0.7, 0.5, 0.9, 0.4, 0.8, 0.3, 0.6, 0.9, 0.5,
    0.4, 0.8, 0.3, 0.7, 0.5, 0.9, 0.4, 0.6, 0.8, 0.3,
  ];

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    return Row(
      children: [
        // Delete button
        IconButton(
          tooltip: 'Delete recording',
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: widget.onDelete,
        ),
        // Pulsing mic icon
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, child) => Icon(
            Icons.mic_rounded,
            color: widget.isPaused
                ? cs.onSurface.withValues(alpha: 0.4)
                : Color.lerp(Colors.red, Colors.redAccent, _pulseCtrl.value)!,
            size: 20,
          ),
        ),
        const SizedBox(width: 6),
        // Timer
        Text(
          _fmt(widget.seconds),
          style: TextStyle(
            color: cs.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 8),
        // Animated waveform bars
        Expanded(
          child: AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, child) {
              return SizedBox(
                height: 28,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(_wave.length, (i) {
                    double h = _wave[i];
                    if (!widget.isPaused) {
                      const twoPi = 2.0 * 3.14159265;
                      final phase =
                          (i / _wave.length * twoPi) +
                          _pulseCtrl.value * twoPi;
                      final bump = (phase % twoPi) / twoPi;
                      h = (h + 0.3 * (0.5 - (bump - 0.5).abs())).clamp(
                        0.1,
                        1.0,
                      );
                    }
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: 3,
                      height: 4 + h * 18,
                      decoration: BoxDecoration(
                        color: widget.isPaused
                            ? cs.onSurface.withValues(alpha: 0.25)
                            : Colors.red.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 6),
        // Pause / Resume
        IconButton(
          tooltip: widget.isPaused ? 'Resume' : 'Pause',
          icon: Icon(
            widget.isPaused
                ? Icons.play_arrow_rounded
                : Icons.pause_rounded,
            color: cs.onSurface,
          ),
          onPressed: widget.onTogglePause,
        ),
        // Send button
        FloatingActionButton.small(
          heroTag: 'sendVoice',
          onPressed: widget.onSend,
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          child: widget.isSending
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.onPrimary,
                  ),
                )
              : const Icon(Icons.send_rounded, size: 18),
        ),
      ],
    );
  }
}
