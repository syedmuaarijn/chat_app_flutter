import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/providers/auth_provider.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:chat_app_flutter/screens/chat_room_screen.dart';
import 'package:chat_app_flutter/screens/create_group_screen.dart';
import 'package:chat_app_flutter/screens/new_chat_screen.dart';
import 'package:chat_app_flutter/screens/settings_screen.dart';
import 'package:chat_app_flutter/widgets/home/conversation_tile.dart';
import 'package:chat_app_flutter/widgets/home/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  void _load() {
    final chatProvider = context.read<ChatProvider>();
    chatProvider.loadConversations();
    chatProvider.listenToConversations();
  }

  @override
  void dispose() {
    context.read<ChatProvider>().stopListeningToConversations();
    super.dispose();
  }

  Future<void> _handleLogout() async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _openConversation(ConversationModel conversation) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          conversationId: conversation.id,
          conversation: conversation,
        ),
      ),
    ).then((_) {
      if (mounted) context.read<ChatProvider>().loadConversations();
    });
  }

  void _openNewChat() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NewChatScreen()),
    ).then((_) {
      if (mounted) context.read<ChatProvider>().loadConversations();
    });
  }

  void _openCreateGroup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
    ).then((_) {
      if (mounted) context.read<ChatProvider>().loadConversations();
    });
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    ).then((_) {
      if (mounted) {
        context.read<ChatProvider>().loadConversations();
        context.read<AuthProvider>().refreshUser();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelColor = colorScheme.onSurface.withValues(alpha: 0.8);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          _currentTab == 0 ? 'Messages' : 'Groups',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        automaticallyImplyLeading: false,
        actions: [
          if (_currentTab == 0)
            IconButton(
              icon: const Icon(Icons.person_add_outlined),
              tooltip: 'New Chat',
              onPressed: _openNewChat,
            ),
          if (_currentTab == 1)
            IconButton(
              icon: const Icon(Icons.group_add_outlined),
              tooltip: 'New Group',
              onPressed: _openCreateGroup,
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: Consumer<ChatProvider>(
        builder: (context, chatProvider, _) {
          final conversations = _currentTab == 0
              ? chatProvider.conversations.where((c) => !c.isGroup).toList()
              : chatProvider.conversations.where((c) => c.isGroup).toList();

          if (chatProvider.isConversationsLoading && chatProvider.conversations.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (conversations.isEmpty) {
            return EmptyConversations(
              icon: _currentTab == 0 ? Icons.chat_bubble_outline_rounded : Icons.group_outlined,
              message: _currentTab == 0
                  ? 'No conversations yet.\nStart a new chat!'
                  : 'No groups yet.\nCreate a group!',
            );
          }

          return RefreshIndicator(
            onRefresh: () => chatProvider.loadConversations(),
            child: ListView.separated(
              itemCount: conversations.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                indent: 72,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              itemBuilder: (context, index) {
                final conversation = conversations[index];

                return Dismissible(
                  key: Key(conversation.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
                    return await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Chat?'),
                        content: const Text(
                            'This will delete all messages in this conversation permanently for you.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                  },
                  onDismissed: (direction) async {
                    final success =
                        await chatProvider.deleteConversation(conversation.id);
                    if (!success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                chatProvider.error ?? 'Failed to delete conversation')),
                      );
                    }
                  },
                  child: ConversationTile(
                    conversation: conversation,
                    onTap: () => _openConversation(conversation),
                  ),
                );
              },
            ),
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded, color: labelColor),
            selectedIcon: Icon(Icons.chat_bubble_rounded, color: colorScheme.primary),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined, color: labelColor),
            selectedIcon: Icon(Icons.groups, color: colorScheme.primary),
            label: 'Groups',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined, color: labelColor),
            selectedIcon: Icon(Icons.settings, color: colorScheme.primary),
            label: 'Settings',
          ),
        ],
        onDestinationSelected: (index) {
          if (index == 2) {
            _openSettings();
          } else {
            setState(() => _currentTab = index);
          }
        },
      ),
    );
  }
}
