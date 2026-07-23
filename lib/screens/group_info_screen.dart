import 'dart:io';
import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:chat_app_flutter/screens/chat_room_screen.dart';
import 'package:chat_app_flutter/services/conversation_service.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

class GroupInfoScreen extends StatefulWidget {
  final String conversationId;
  final ConversationModel conversation;

  const GroupInfoScreen({
    super.key,
    required this.conversationId,
    required this.conversation,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final String _currentUserId =
      Supabase.instance.client.auth.currentUser?.id ?? '';

  late bool _onlyAdminsCanMessage;
  late bool _onlyAdminsCanEditInfo;
  bool _isCreator = false;
  bool _isAdmin = false;
  String _groupName = '';
  String _groupDescription = '';
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _groupName = widget.conversation.displayName;
    _groupDescription = widget.conversation.description ?? '';
    _onlyAdminsCanMessage = widget.conversation.onlyAdminsCanMessage;
    _onlyAdminsCanEditInfo = widget.conversation.onlyAdminsCanEditInfo;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final chatProvider = context.read<ChatProvider>();
    await chatProvider.loadGroupParticipants(widget.conversationId);
    await chatProvider.loadCurrentUserRole(widget.conversationId);

    // Reload settings from the provider's live conversation data
    final updatedConv = chatProvider.conversations.firstWhere(
      (c) => c.id == widget.conversationId,
      orElse: () => widget.conversation,
    );

    if (mounted) {
      setState(() {
        _onlyAdminsCanMessage = updatedConv.onlyAdminsCanMessage;
        _onlyAdminsCanEditInfo = updatedConv.onlyAdminsCanEditInfo;
        _groupName = updatedConv.displayName;
        _groupDescription = updatedConv.description ?? '';
        _isCreator = chatProvider.currentUserRole == 'creator';
        _isAdmin = chatProvider.currentUserRole == 'admin' || _isCreator;
      });
    }
  }

  Future<void> _pickAndUploadGroupImage() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo Library'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    setState(() => _isUploading = true);

    try {
      final file = File(pickedFile.path);
      final conversationService = ConversationService();
      final url = await conversationService.uploadGroupAvatar(widget.conversationId, file);
      
      if (!mounted) return;
      final chatProvider = context.read<ChatProvider>();
      final success = await chatProvider.updateGroupInfo(
        conversationId: widget.conversationId,
        avatarUrl: url,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group profile picture updated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update group image: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _showEditInfoDialog() {
    final nameCtrl = TextEditingController(text: _groupName);
    final descCtrl = TextEditingController(text: _groupDescription == '0 participants' || _groupDescription == '1 participants' ? '' : _groupDescription);
    final canEdit = !_onlyAdminsCanEditInfo || _isAdmin;

    if (!canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only admins can edit group info')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Group Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Group name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final name = nameCtrl.text.trim();
              final desc = descCtrl.text.trim();
              if (name.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Group name cannot be empty'), backgroundColor: Colors.red),
                  );
                }
                return;
              }
              final chatProvider = context.read<ChatProvider>();
              final success = await chatProvider.updateGroupInfo(
                conversationId: widget.conversationId,
                name: name != widget.conversation.displayName ? name : null,
                description: desc.isNotEmpty ? desc : null,
              );
              if (success && mounted) {
                setState(() {
                  _groupName = name;
                  _groupDescription = desc;
                });
              }
            },
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMessageSetting(bool value) async {
    final chatProvider = context.read<ChatProvider>();
    final success = await chatProvider.updateGroupSettings(
      conversationId: widget.conversationId,
      onlyAdminsCanMessage: value,
    );
    if (success && mounted) {
      setState(() => _onlyAdminsCanMessage = value);
    }
  }

  Future<void> _toggleEditInfoSetting(bool value) async {
    final chatProvider = context.read<ChatProvider>();
    final success = await chatProvider.updateGroupSettings(
      conversationId: widget.conversationId,
      onlyAdminsCanEditInfo: value,
    );
    if (success && mounted) {
      setState(() => _onlyAdminsCanEditInfo = value);
    }
  }

  void _showParticipantOptions(ParticipantInfo participant) {
    final isTargetMe = participant.userId == _currentUserId;
    final isTargetCreator = participant.role == 'creator';
    final isTargetAdmin = participant.role == 'admin';
    final canPromote = _isAdmin && participant.role == 'member';
    final canDemote = _isCreator && participant.role == 'admin';
    final canRemove =
        !isTargetMe && !isTargetCreator && (_isCreator || (_isAdmin && participant.role == 'member'));

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    backgroundImage: participant.user?.avatarUrl.isNotEmpty == true
                        ? CachedNetworkImageProvider(participant.user!.avatarUrl)
                        : null,
                    child: participant.user?.avatarUrl.isEmpty ?? true
                        ? Text(
                            _displayName(participant)[0].toUpperCase(),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _displayName(participant),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (isTargetCreator)
                    Text(
                      'Creator',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else if (isTargetAdmin)
                    Text(
                      'Admin',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.tertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (!isTargetMe)
              ListTile(
                leading: const Icon(Icons.chat_outlined),
                title: const Text('Message User'),
                onTap: () {
                  Navigator.pop(ctx);
                  _startChatWith(participant);
                },
              ),
            if (canPromote)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Make Admin'),
                onTap: () {
                  Navigator.pop(ctx);
                  _promoteToAdmin(participant.userId);
                },
              ),
            if (canDemote)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Dismiss as Admin'),
                onTap: () {
                  Navigator.pop(ctx);
                  _demoteFromAdmin(participant.userId);
                },
              ),
            if (canRemove)
              ListTile(
                leading: Icon(Icons.remove_circle_outline, color: Colors.red),
                title: Text('Remove from group', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmRemove(participant);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _displayName(ParticipantInfo p) {
    final user = p.user;
    if (user != null && user.fullName.isNotEmpty) return user.fullName;
    if (user != null && user.username.isNotEmpty) return user.username;
    return 'User';
  }

  Future<void> _startChatWith(ParticipantInfo participant) async {
    final chatProvider = context.read<ChatProvider>();
    final convId = await chatProvider.getOrCreateConversation(participant.userId);
    if (!mounted) return;
    if (convId == null) return;

    final conv = chatProvider.conversations.firstWhere(
      (c) => c.id == convId,
      orElse: () => widget.conversation,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          conversationId: convId,
          conversation: conv,
        ),
      ),
    );
  }

  Future<void> _promoteToAdmin(String userId) async {
    final chatProvider = context.read<ChatProvider>();
    final success = await chatProvider.promoteToAdmin(widget.conversationId, userId);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Promoted to admin')),
      );
      await _refreshRole();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(chatProvider.error ?? 'Failed to promote'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _demoteFromAdmin(String userId) async {
    final chatProvider = context.read<ChatProvider>();
    final success = await chatProvider.demoteFromAdmin(widget.conversationId, userId);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demoted from admin')),
      );
      await _refreshRole();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(chatProvider.error ?? 'Failed to demote'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _refreshRole() async {
    final chatProvider = context.read<ChatProvider>();
    await chatProvider.loadCurrentUserRole(widget.conversationId);
    if (mounted) {
      setState(() {
        _isCreator = chatProvider.currentUserRole == 'creator';
        _isAdmin = chatProvider.currentUserRole == 'admin' || _isCreator;
      });
    }
  }

  Future<void> _confirmRemove(ParticipantInfo participant) async {
    final name = _displayName(participant);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member?'),
        content: Text('Remove $name from this group?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final chatProvider = context.read<ChatProvider>();
      final success = await chatProvider.removeGroupParticipant(
        widget.conversationId,
        participant.userId,
      );
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(chatProvider.error ?? 'Failed to remove'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addParticipants() async {
    final chatProvider = context.read<ChatProvider>();
    await chatProvider.loadAllUsers();

    if (!mounted) return;

    final currentMemberIds = chatProvider.groupParticipants
        .where((p) => p.status == 'active')
        .map((p) => p.userId)
        .toSet();

    final availableUsers = chatProvider.users
        .where((u) => !currentMemberIds.contains(u.id))
        .toList();

    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddParticipantsSheet(availableUsers: availableUsers),
    );

    if (selected != null && selected.isNotEmpty && mounted) {
      final success = await chatProvider.addGroupParticipants(
        widget.conversationId,
        selected.toList(),
      );
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(chatProvider.error ?? 'Failed to add members'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _leaveGroup() async {
    if (_isCreator) {
      _showCreatorLeaveOptions();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Group?'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final chatProvider = context.read<ChatProvider>();
      final success = await chatProvider.leaveGroup(widget.conversationId);
      if (success && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(chatProvider.error ?? 'Failed to leave group'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showCreatorLeaveOptions() {
    final chatProvider = context.read<ChatProvider>();
    final admins = chatProvider.groupParticipants
        .where((p) => p.role == 'admin' && p.status == 'active')
        .toList();

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'You are the creator. What would you like to do?',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (admins.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Transfer ownership and leave'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showTransferOwnership(admins);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Delete group permanently',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteGroup();
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showTransferOwnership(List<ParticipantInfo> admins) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Transfer ownership to:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ...admins.map((admin) => ListTile(
              leading: CircleAvatar(
                child: Text(_displayName(admin)[0].toUpperCase()),
              ),
              title: Text(_displayName(admin)),
              subtitle: const Text('Admin'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmTransfer(admin.userId);
              },
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmTransfer(String newCreatorId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transfer Ownership?'),
        content: const Text('You will be demoted to admin. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Transfer & Leave'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final chatProvider = context.read<ChatProvider>();
      await chatProvider.transferOwnership(widget.conversationId, newCreatorId);
      await chatProvider.leaveGroup(widget.conversationId);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  Future<void> _confirmDeleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Group?'),
        content: const Text('This will permanently delete the group and all messages for everyone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final chatProvider = context.read<ChatProvider>();
      final success = await chatProvider.deleteGroup(widget.conversationId);
      if (success && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(chatProvider.error ?? 'Failed to delete group'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImageViewer(String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ImageViewerScreen(imageUrl: imageUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Group Info', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Consumer<ChatProvider>(
        builder: (context, chatProvider, _) {
          if (chatProvider.isGroupParticipantsLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final participants = chatProvider.groupParticipants
              .where((p) => p.status == 'active')
              .toList();

          final activeCount = participants.length;

          final updatedConv = chatProvider.conversations.firstWhere(
            (c) => c.id == widget.conversationId,
            orElse: () => widget.conversation,
          );

          return SingleChildScrollView(
            child: Column(
              children: [
                // ── Header (tappable for admins to edit) ────────────
                GestureDetector(
                  onTap: _isAdmin ? _showEditInfoDialog : null,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            GestureDetector(
                              onTap: updatedConv.avatarUrl?.isNotEmpty == true
                                  ? () => _showImageViewer(updatedConv.avatarUrl!)
                                  : (_isAdmin && !_isUploading ? _pickAndUploadGroupImage : null),
                              child: CircleAvatar(
                                radius: 44,
                                backgroundColor: colorScheme.primaryContainer,
                                backgroundImage: updatedConv.avatarUrl?.isNotEmpty == true
                                    ? CachedNetworkImageProvider(updatedConv.avatarUrl!)
                                    : null,
                                child: updatedConv.avatarUrl?.isEmpty ?? true
                                    ? Icon(Icons.group, size: 40, color: colorScheme.onPrimaryContainer)
                                    : null,
                              ),
                            ),
                            if (_isAdmin)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: _isUploading ? null : _pickAndUploadGroupImage,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: colorScheme.surface, width: 1.5),
                                    ),
                                    child: Icon(Icons.camera_alt, size: 14, color: colorScheme.onPrimary),
                                  ),
                                ),
                              ),
                            if (_isUploading)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (_isAdmin)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Tap to edit name & bio',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.primary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                _groupName,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                        if (_groupDescription.isNotEmpty &&
                            _groupDescription != '0 participants' &&
                            _groupDescription != '1 participants')
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _groupDescription,
                              style: TextStyle(
                                color: colorScheme.onSurface.withValues(alpha: 0.6),
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          '${widget.conversation.participantCount > 0 ? widget.conversation.participantCount : activeCount} participants',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Settings (admins only) ──────────────────────────
                if (_isAdmin) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Group Settings',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                  _SettingsTile(
                    title: 'Edit group info',
                    subtitle: _onlyAdminsCanEditInfo
                        ? 'Only admins can change name & bio'
                        : 'All members can change name & bio',
                    value: _onlyAdminsCanEditInfo,
                    onChanged: _toggleEditInfoSetting,
                  ),
                  _SettingsTile(
                    title: 'Send messages',
                    subtitle: _onlyAdminsCanMessage
                        ? 'Only admins can send messages'
                        : 'All members can send messages',
                    value: _onlyAdminsCanMessage,
                    onChanged: _toggleMessageSetting,
                  ),
                ],

                // ── Participants list ──────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Participants ($activeCount)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      if (_isAdmin)
                        TextButton.icon(
                          onPressed: _addParticipants,
                          icon: const Icon(Icons.person_add_alt, size: 18),
                          label: const Text('Add'),
                        ),
                    ],
                  ),
                ),

                ...participants.map((p) => _ParticipantTile(
                  participant: p,
                  isCurrentUser: p.userId == _currentUserId,
                  onTap: () => _showParticipantOptions(p),
                )),

                // ── Exit / Delete group ────────────────────────────
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _leaveGroup,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(_isCreator ? Icons.delete_forever : Icons.exit_to_app),
                      label: Text(
                        _isCreator ? 'Delete Group' : 'Exit Group',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Settings toggle tile ────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            title == 'Send messages' ? Icons.send : Icons.edit_note,
            size: 22,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value ? 'On' : 'Off',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: value ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ── Participant list tile ───────────────────────────────────────────────────

class _ParticipantTile extends StatelessWidget {
  final ParticipantInfo participant;
  final bool isCurrentUser;
  final VoidCallback onTap;

  const _ParticipantTile({
    required this.participant,
    required this.isCurrentUser,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = participant.user;
    final displayName = user != null
        ? (user.fullName.isNotEmpty ? user.fullName : user.username)
        : 'Unknown';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: colorScheme.primaryContainer,
        backgroundImage: user?.avatarUrl.isNotEmpty == true
            ? CachedNetworkImageProvider(user!.avatarUrl)
            : null,
        child: user?.avatarUrl.isEmpty ?? true
            ? Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                style: TextStyle(color: colorScheme.onPrimaryContainer),
              )
            : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              displayName,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCurrentUser)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                'You',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
      subtitle: participant.role == 'creator'
          ? Text(
              'Creator',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            )
          : participant.role == 'admin'
              ? Text(
                  'Admin',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.tertiary,
                    fontWeight: FontWeight.w500,
                  ),
                )
              : null,
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}

class _ImageViewerScreen extends StatelessWidget {
  final String imageUrl;

  const _ImageViewerScreen({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            errorWidget: (context, url, error) =>
                const Icon(Icons.error, color: Colors.white, size: 64),
          ),
        ),
      ),
    );
  }
}

// ── Add Participants Bottom Sheet ───────────────────────────────────────────

class _AddParticipantsSheet extends StatefulWidget {
  final List<dynamic> availableUsers;

  const _AddParticipantsSheet({required this.availableUsers});

  @override
  State<_AddParticipantsSheet> createState() => _AddParticipantsSheetState();
}

class _AddParticipantsSheetState extends State<_AddParticipantsSheet> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Add Members',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                TextButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selected),
                  child: Text(
                    'Add (${_selected.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: widget.availableUsers.isEmpty
                ? Center(
                    child: Text(
                      'No more users to add',
                      style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.4)),
                    ),
                  )
                : ListView.builder(
                    itemCount: widget.availableUsers.length,
                    itemBuilder: (context, index) {
                      final user = widget.availableUsers[index];
                      final isSelected = _selected.contains(user.id);
                      final displayName = user.fullName.isNotEmpty ? user.fullName : user.username;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: colorScheme.primaryContainer,
                          backgroundImage: user.avatarUrl.isNotEmpty
                              ? CachedNetworkImageProvider(user.avatarUrl)
                              : null,
                          child: user.avatarUrl.isEmpty
                              ? Text(displayName[0].toUpperCase())
                              : null,
                        ),
                        title: Text(displayName),
                        subtitle: Text('@${user.username}'),
                        trailing: isSelected
                            ? Icon(Icons.check_circle, color: colorScheme.primary)
                            : Icon(Icons.circle_outlined, color: colorScheme.outline),
                        onTap: () {
                          setState(() {
                            if (_selected.contains(user.id)) {
                              _selected.remove(user.id);
                            } else {
                              _selected.add(user.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
