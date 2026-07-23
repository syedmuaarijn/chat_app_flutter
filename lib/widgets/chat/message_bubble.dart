import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chat_app_flutter/models/message_model.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:chat_app_flutter/widgets/chat/message_info_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';

class MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final bool isGroup;
  final Future<void> Function(MessageModel message)? onForward;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.isGroup = false,
    this.onForward,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  String? get _copyableText {
    if (widget.message.type == 'text') return widget.message.content;
    final caption = widget.message.content;
    return caption.isNotEmpty && caption != widget.message.fileName
        ? caption
        : null;
  }

  void _showMessageActions(BuildContext context) {
    final copyableText = _copyableText;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            if (copyableText != null)
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Copy'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: copyableText));
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  }
                },
              ),
            if (widget.onForward != null)
              ListTile(
                leading: const Icon(Icons.forward_outlined),
                title: const Text('Forward'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await widget.onForward!(widget.message);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetContext);
                _showDeleteDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    final chatProvider = context.read<ChatProvider>();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Message?'),
        content: const Text('Choose how you want to delete this message.'),
        actions: [
          if (widget.isMe)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Message Info'),
              onTap: () {
                Navigator.pop(dialogCtx);
                showModalBottomSheet(
                  context: context,
                  builder: (_) =>
                      MessageInfoSheet(messageId: widget.message.id),
                );
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _confirmDelete(
                context,
                () async {
                  final success = await chatProvider.deleteMessageForMe(
                    widget.message.id,
                  );
                  if (!success && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          chatProvider.error ?? 'Failed to delete message',
                        ),
                      ),
                    );
                  }
                },
                'Delete for me',
                'Are you sure you want to delete this message for yourself?',
              );
            },
            child: const Text('Delete for Me'),
          ),
          if (widget.isMe)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () {
                Navigator.pop(dialogCtx);
                _confirmDelete(
                  context,
                  () async {
                    final success = await chatProvider.deleteMessageForEveryone(
                      widget.message.id,
                    );
                    if (!success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            chatProvider.error ?? 'Failed to delete message',
                          ),
                        ),
                      );
                    }
                  },
                  'Delete for everyone',
                  'Are you sure you want to delete this message for everyone?',
                );
              },
              child: const Text('Delete for Everyone'),
            ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    VoidCallback onConfirm,
    String title,
    String description,
  ) {
    showDialog(
      context: context,
      builder: (confirmCtx) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(confirmCtx);
              onConfirm();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  static Color _userNameColor(String userId) {
    final hash = userId.hashCode;
    final hue = (hash % 360).abs();
    return HSLColor.fromAHSL(1.0, hue.toDouble(), 0.6, 0.5).toColor();
  }

  String _fileName() {
    final name =
        widget.message.fileName ??
        'file_${DateTime.now().millisecondsSinceEpoch}';
    return name.replaceAll(RegExp(r'[/\\]'), '_');
  }

  Future<File> _getMediaFile({required bool savePermanently}) async {
    final mediaUrl = widget.message.mediaUrl;
    if (mediaUrl == null || mediaUrl.isEmpty) {
      throw Exception('This attachment does not have a file URL.');
    }

    if (!mediaUrl.startsWith('http')) {
      final localFile = File(mediaUrl);
      if (await localFile.exists()) {
        return localFile;
      }
      throw Exception(
        'The selected file is no longer available on this device.',
      );
    }

    final directory = savePermanently
        ? await getApplicationDocumentsDirectory()
        : await getTemporaryDirectory();
    await directory.create(recursive: true);
    final file = File('${directory.path}/${_fileName()}');

    final client = http.Client();
    try {
      final response = await client.send(
        http.Request('GET', Uri.parse(mediaUrl)),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Download failed with status ${response.statusCode}.',
        );
      }

      final contentLength =
          response.contentLength ?? widget.message.fileSize ?? 0;
      final sink = file.openWrite();
      var downloaded = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          downloaded += chunk.length;
          if (contentLength > 0 && mounted) {
            setState(() => _downloadProgress = downloaded / contentLength);
          }
        }
      } finally {
        await sink.close();
      }
      return file;
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<void> _openFile(File file) async {
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception(
        result.message.isEmpty
            ? 'No compatible app was found to open this file.'
            : result.message,
      );
    }
  }

  Future<void> _openMedia() async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      await _openFile(await _getMediaFile(savePermanently: false));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0;
        });
      }
    }
  }

  Future<void> _downloadAndSaveFile() async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      final file = await _getMediaFile(savePermanently: true);
      if (mounted) {
        setState(() => _downloadProgress = 1);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved to app documents: ${file.path.split('/').last}',
            ),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => _openFile(file),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0;
        });
      }
    }
  }

  Widget _getDocumentIcon(String? fileName) {
    final ext = fileName != null && fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    Color iconColor = Colors.blue;
    IconData iconData = Icons.insert_drive_file;

    if (ext == 'pdf') {
      iconColor = Colors.red;
      iconData = Icons.picture_as_pdf;
    } else if (['doc', 'docx'].contains(ext)) {
      iconColor = Colors.blue;
      iconData = Icons.description;
    } else if (['xls', 'xlsx'].contains(ext)) {
      iconColor = Colors.green;
      iconData = Icons.table_chart;
    } else if (['ppt', 'pptx'].contains(ext)) {
      iconColor = Colors.orange;
      iconData = Icons.slideshow;
    } else if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      iconColor = Colors.amber;
      iconData = Icons.folder_zip;
    } else if (ext == 'apk') {
      iconColor = Colors.lightGreen;
      iconData = Icons.android;
    }

    return CircleAvatar(
      radius: 20,
      backgroundColor: iconColor.withValues(alpha: 0.2),
      child: Icon(iconData, color: iconColor, size: 22),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildMediaContent(
    BuildContext context,
    Color textColor,
    Color timeColor,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSending = widget.message.status == MessageStatus.sending;

    switch (widget.message.type) {
      case 'image':
        final isHttp =
            widget.message.mediaUrl != null &&
            widget.message.mediaUrl!.startsWith('http');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                GestureDetector(
                  onTap: _openMedia,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: isHttp
                        ? CachedNetworkImage(
                            imageUrl: widget.message.mediaUrl!,
                            placeholder: (_, _) => Container(
                              height: 180,
                              color: Colors.black12,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            errorWidget: (_, _, _) => Container(
                              height: 150,
                              color: Colors.black12,
                              child: const Icon(Icons.broken_image, size: 40),
                            ),
                            fit: BoxFit.cover,
                          )
                        : widget.message.mediaUrl != null
                        ? Image.file(
                            File(widget.message.mediaUrl!),
                            fit: BoxFit.cover,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                if (isSending)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 8),
                            Text(
                              'Uploading...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!isSending && isHttp)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        icon: _isDownloading
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  value: _downloadProgress > 0
                                      ? _downloadProgress
                                      : null,
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.download,
                                size: 16,
                                color: Colors.white,
                              ),
                        padding: EdgeInsets.zero,
                        onPressed: _isDownloading ? null : _downloadAndSaveFile,
                      ),
                    ),
                  ),
              ],
            ),
            if (widget.message.content.isNotEmpty &&
                widget.message.content != widget.message.fileName) ...[
              const SizedBox(height: 6),
              Text(
                widget.message.content,
                style: TextStyle(color: textColor, fontSize: 15),
              ),
            ],
          ],
        );

      case 'video':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                GestureDetector(
                  onTap: _openMedia,
                  child: Container(
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(
                          Icons.play_circle_fill,
                          size: 54,
                          color: Colors.white,
                        ),
                        Positioned(
                          bottom: 8,
                          left: 8,
                          right: 8,
                          child: Text(
                            widget.message.fileName ?? 'Video',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isSending)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 8),
                            Text(
                              'Uploading...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!isSending)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        icon: _isDownloading
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  value: _downloadProgress > 0
                                      ? _downloadProgress
                                      : null,
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.download,
                                size: 16,
                                color: Colors.white,
                              ),
                        padding: EdgeInsets.zero,
                        onPressed: _isDownloading ? null : _downloadAndSaveFile,
                      ),
                    ),
                  ),
              ],
            ),
            if (widget.message.content.isNotEmpty &&
                widget.message.content != widget.message.fileName) ...[
              const SizedBox(height: 6),
              Text(
                widget.message.content,
                style: TextStyle(color: textColor, fontSize: 15),
              ),
            ],
          ],
        );

      case 'audio':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: isSending ? null : _openMedia,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: widget.isMe
                      ? Colors.white24
                      : colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.orange,
                      child: Icon(Icons.headset, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.message.fileName ?? 'Audio',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: textColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.message.fileSize != null)
                            Text(
                              _formatFileSize(widget.message.fileSize!),
                              style: TextStyle(fontSize: 11, color: timeColor),
                            ),
                        ],
                      ),
                    ),
                    if (isSending)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        icon: _isDownloading
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  value: _downloadProgress > 0
                                      ? _downloadProgress
                                      : null,
                                  strokeWidth: 2,
                                  color: textColor,
                                ),
                              )
                            : Icon(
                                Icons.download_rounded,
                                size: 24,
                                color: textColor,
                              ),
                        onPressed: _isDownloading ? null : _downloadAndSaveFile,
                      ),
                  ],
                ),
              ),
            ),
            if (widget.message.content.isNotEmpty &&
                widget.message.content != widget.message.fileName) ...[
              const SizedBox(height: 6),
              Text(
                widget.message.content,
                style: TextStyle(color: textColor, fontSize: 15),
              ),
            ],
          ],
        );

      case 'voice':
        return _VoiceMessagePlayer(
          url: widget.message.mediaUrl,
          fallbackDurationSeconds: widget.message.audioDuration,
          isMe: widget.isMe,
          foregroundColor: textColor,
          mutedColor: timeColor,
        );

      case 'document':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: isSending ? null : _openMedia,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.isMe
                      ? Colors.white24
                      : colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _getDocumentIcon(widget.message.fileName),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.message.fileName ?? 'Document',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: textColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          if (widget.message.fileSize != null)
                            Text(
                              _formatFileSize(widget.message.fileSize!),
                              style: TextStyle(fontSize: 11, color: timeColor),
                            ),
                        ],
                      ),
                    ),
                    if (isSending)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        icon: _isDownloading
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  value: _downloadProgress > 0
                                      ? _downloadProgress
                                      : null,
                                  strokeWidth: 2,
                                  color: textColor,
                                ),
                              )
                            : Icon(
                                Icons.download_rounded,
                                size: 24,
                                color: textColor,
                              ),
                        onPressed: _isDownloading ? null : _downloadAndSaveFile,
                      ),
                  ],
                ),
              ),
            ),
            if (widget.message.content.isNotEmpty &&
                widget.message.content != widget.message.fileName) ...[
              const SizedBox(height: 6),
              Text(
                widget.message.content,
                style: TextStyle(color: textColor, fontSize: 15),
              ),
            ],
          ],
        );

      case 'text':
      default:
        return Text(
          widget.message.content,
          style: TextStyle(color: textColor, fontSize: 15),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (widget.message.isSystemMessage) {
      return _SystemBubble(message: widget.message, colorScheme: colorScheme);
    }

    final isDeleted = widget.message.content == '[This message was deleted]';

    final bubbleColor = widget.isMe
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest;
    final textColor = widget.isMe
        ? colorScheme.onPrimary
        : colorScheme.onSurface;
    final timeColor = widget.isMe
        ? colorScheme.onPrimary.withValues(alpha: 0.7)
        : colorScheme.onSurface.withValues(alpha: 0.5);

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: isDeleted ? null : () => _showMessageActions(context),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Column(
            crossAxisAlignment: widget.isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              // Sender name for incoming group messages
              if (widget.isGroup &&
                  !widget.isMe &&
                  widget.message.senderUsername != null &&
                  !isDeleted)
                Padding(
                  padding: const EdgeInsets.only(left: 14, bottom: 2),
                  child: Text(
                    widget.message.senderUsername!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _userNameColor(widget.message.senderId ?? ''),
                    ),
                  ),
                ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(widget.isMe ? 18 : 4),
                    bottomRight: Radius.circular(widget.isMe ? 4 : 18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.message.isForwarded && !isDeleted)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.forward, size: 13, color: timeColor),
                            const SizedBox(width: 4),
                            Text(
                              'Forwarded',
                              style: TextStyle(
                                color: timeColor,
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (isDeleted)
                      Text(
                        'This message was deleted',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.6),
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else
                      _buildMediaContent(context, textColor, timeColor),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _timeAgo(widget.message.createdAt),
                          style: TextStyle(fontSize: 10, color: timeColor),
                        ),
                        if (widget.isMe && !isDeleted) ...[
                          const SizedBox(width: 4),
                          _StatusIcon(status: widget.message.status),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final local = dt.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) {
      final h = local.hour.toString().padLeft(2, '0');
      final m = local.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${local.day}/${local.month}';
  }
}

class _SystemBubble extends StatelessWidget {
  final MessageModel message;
  final ColorScheme colorScheme;

  const _SystemBubble({required this.message, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.content,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final MessageStatus status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == MessageStatus.read
        ? const Color(0xFF53BDEB)
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

    switch (status) {
      case MessageStatus.sending:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
        );
      case MessageStatus.sent:
        return Icon(Icons.check, size: 14, color: color);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: 14, color: color);
      case MessageStatus.read:
        return Icon(Icons.done_all, size: 14, color: color);
    }
  }
}

/// An in-chat player for a voice note. Audio stays inside the app instead of
/// being handed off to the device's default audio application.
class _VoiceMessagePlayer extends StatefulWidget {
  final String? url;
  final int? fallbackDurationSeconds;
  final bool isMe;
  final Color foregroundColor;
  final Color mutedColor;

  const _VoiceMessagePlayer({
    required this.url,
    required this.fallbackDurationSeconds,
    required this.isMe,
    required this.foregroundColor,
    required this.mutedColor,
  });

  @override
  State<_VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<_VoiceMessagePlayer>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _isLoading = false;
  bool _hasError = false;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _player.positionStream.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _player.durationStream.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.playing) {
        _waveController.repeat(reverse: true);
      } else {
        _waveController.stop();
      }
      if (state.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
      }
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _ensureSourceLoaded() async {
    if (_player.audioSource != null) return;
    if (widget.url == null || widget.url!.isEmpty) return;
    if (mounted) setState(() { _isLoading = true; _hasError = false; });
    try {
      final url = widget.url!;
      if (url.startsWith('http')) {
        await _player.setUrl(url);
      } else {
        await _player.setFilePath(url);
      }
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
      rethrow;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Duration get _totalDuration =>
      _duration ?? Duration(seconds: widget.fallbackDurationSeconds ?? 0);

  String _format(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _togglePlayback() async {
    if (_isLoading || widget.url == null || widget.url!.isEmpty) return;
    try {
      if (_player.playing) {
        await _player.pause();
        return;
      }
      await _ensureSourceLoaded();
      if (!_hasError) await _player.play();
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  Future<void> _seekTo(double value) async {
    final total = _totalDuration;
    if (total.inMilliseconds == 0) return;
    try {
      await _ensureSourceLoaded();
      if (_hasError) return;
      final target = Duration(
        milliseconds: (total.inMilliseconds * value).round(),
      );
      await _player.seek(target);
      if (mounted) setState(() => _position = target);
    } catch (_) {
      /* ignore seek errors */
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _totalDuration;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final isPlaying = _player.playing;

    return SizedBox(
      width: 240,
      child: Row(
        children: [
          // Play / Pause button
          GestureDetector(
            onTap: _togglePlayback,
            child: CircleAvatar(
              radius: 22,
              backgroundColor: widget.isMe
                  ? Colors.white24
                  : Theme.of(context).colorScheme.primaryContainer,
              child: _isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: widget.foregroundColor,
                      ),
                    )
                  : Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: widget.foregroundColor,
                      size: 24,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Waveform bars + invisible slider for seeking
                Stack(
                  alignment: Alignment.center,
                  children: [
                    _WaveformBars(
                      progress: progress,
                      isPlaying: isPlaying,
                      animation: _waveController,
                      activeColor: widget.foregroundColor,
                      inactiveColor: widget.mutedColor.withValues(alpha: 0.35),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 0,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                        trackShape: const _TransparentTrackShape(),
                      ),
                      child: Slider(
                        value: progress,
                        activeColor: Colors.transparent,
                        inactiveColor: Colors.transparent,
                        thumbColor: widget.foregroundColor,
                        onChanged:
                            total.inMilliseconds == 0 ? null : _seekTo,
                      ),
                    ),
                  ],
                ),
                // Time label
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    _hasError
                        ? 'Unable to play'
                        : isPlaying
                        ? '${_format(_position)} / ${_format(total)}'
                        : _format(total),
                    style: TextStyle(fontSize: 11, color: widget.mutedColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws fake waveform bars. Bars at positions ≤ [progress] are "active"
/// (played), the rest are "inactive". While [isPlaying], bar heights animate.
class _WaveformBars extends StatelessWidget {
  final double progress;
  final bool isPlaying;
  final Animation<double> animation;
  final Color activeColor;
  final Color inactiveColor;

  const _WaveformBars({
    required this.progress,
    required this.isPlaying,
    required this.animation,
    required this.activeColor,
    required this.inactiveColor,
  });

  static const List<double> _seed = [
    0.30, 0.60, 0.40, 0.90, 0.50, 0.70, 0.30, 0.80, 0.50, 0.40,
    0.90, 0.60, 0.30, 0.70, 0.50, 0.80, 0.40, 0.60, 0.30, 0.70,
    0.50, 0.90, 0.40, 0.80, 0.30, 0.60, 0.50, 0.90, 0.40, 0.70,
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) {
        const count = 30;
        const twoPi = 2.0 * 3.14159265;
        return SizedBox(
          height: 32,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(count, (i) {
              final fraction = i / count;
              final isActive = fraction <= progress;
              double h = _seed[i];
              if (isPlaying) {
                final phase = (fraction * twoPi) + animation.value * twoPi;
                final wave = (phase % twoPi) / twoPi;
                h = (h + 0.2 * (0.5 - (wave - 0.5).abs())).clamp(0.1, 1.0);
              }
              return AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                width: 3,
                height: 4 + h * 22,
                decoration: BoxDecoration(
                  color: isActive ? activeColor : inactiveColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

/// A completely transparent track so only the thumb renders over the waveform.
class _TransparentTrackShape extends RoundedRectSliderTrackShape {
  const _TransparentTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    // Intentionally empty — the waveform bars serve as the visual track.
  }
}
