import 'package:chat_app_flutter/models/conversation_model.dart';
import 'package:chat_app_flutter/providers/auth_provider.dart';
import 'package:chat_app_flutter/screens/ai_chat_screen.dart';
import 'package:chat_app_flutter/providers/call_provider.dart';
import 'package:chat_app_flutter/providers/chat_provider.dart';
import 'package:chat_app_flutter/screens/chat_room_screen.dart';
import 'package:chat_app_flutter/screens/create_group_screen.dart';
import 'package:chat_app_flutter/screens/new_chat_screen.dart';
import 'package:chat_app_flutter/screens/settings_screen.dart';
import 'package:chat_app_flutter/screens/profile_settings_screen.dart';
import 'package:chat_app_flutter/screens/calls_screen.dart';
import 'package:chat_app_flutter/services/offline_service.dart';
import 'package:chat_app_flutter/widgets/home/conversation_tile.dart';
import 'package:chat_app_flutter/widgets/home/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/common/abstract_background.dart';
import '../widgets/common/glass_app_bar.dart';
import '../widgets/common/glass_bottom_bar.dart';
import '../widgets/common/glass_search_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final OfflineService _offlineService = OfflineService();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  void _load() {
    final chatProvider = context.read<ChatProvider>();
    chatProvider.loadConversations();
    chatProvider.listenToConversations();
    context.read<CallProvider>().listenToCallSignals();
  }

  @override
  void dispose() {
    context.read<ChatProvider>().stopListeningToConversations();
    context.read<CallProvider>().stopListeningToCallSignals();
    _tabController.dispose();
    super.dispose();
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
      if (!mounted) return;
      _offlineService.hasConnection().then((isOnline) {
        if (isOnline && mounted) {
          context.read<ChatProvider>().loadConversations();
        }
      });
    });
  }

  void _openNewChat() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NewChatScreen()),
    ).then((_) {
      if (!mounted) return;
      _offlineService.hasConnection().then((isOnline) {
        if (isOnline && mounted) {
          context.read<ChatProvider>().loadConversations();
        }
      });
    });
  }

  void _openCreateGroup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
    ).then((_) {
      if (!mounted) return;
      _offlineService.hasConnection().then((isOnline) {
        if (isOnline && mounted) {
          context.read<ChatProvider>().loadConversations();
        }
      });
    });
  }

  void _openProfileSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
    ).then((_) {
      if (!mounted) return;
      _offlineService.hasConnection().then((isOnline) {
        if (isOnline && mounted) {
          context.read<AuthProvider>().refreshUser();
        }
      });
    });
  }

  void _openAiChat() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AiChatScreen()),
    );
  }

  void _deleteConversation(BuildContext context, String id) async {
    final provider = context.read<ChatProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Delete Chat?'),
        content: const Text(
          'This will delete all messages in this conversation permanently for you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await provider.deleteConversation(id);
      if (!success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.error ?? 'Failed to delete conversation')),
        );
      }
    }
  }

  Widget _buildConversationsList(bool isGroup) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        if (!chatProvider.initialLoadDone) {
          return const Center(child: CircularProgressIndicator());
        }

        var conversations = chatProvider.conversations
            .where((c) => c.isGroup == isGroup)
            .toList();

        if (_searchQuery.isNotEmpty) {
          conversations = conversations.where((c) {
            final name = c.displayName;
            return name.toLowerCase().contains(_searchQuery.toLowerCase());
          }).toList();
        }

        if (conversations.isEmpty) {
          return EmptyConversations(
            icon: isGroup ? Icons.group_outlined : Icons.chat_bubble_outline_rounded,
            message: isGroup
                ? 'No groups yet.\nCreate a group!'
                : 'No conversations yet.\nStart a new chat!',
          );
        }

        return RefreshIndicator(
          onRefresh: () => chatProvider.loadConversations(),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              return GestureDetector(
                onLongPress: () => _deleteConversation(context, conversation.id),
                child: ConversationTile(
                  conversation: conversation,
                  onTap: () => _openConversation(conversation),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const AbstractBackground(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsetsGeometry.symmetric(horizontal: 7),
                  child: GlassAppBar(
                    title: 'Yapp',
                    onAvatarTap: _openProfileSettings,
                  ),
                ),
                if (_tabController.index == 0 || _tabController.index == 1)
                  GlassSearchBar(
                    hintText: 'Search chats...',
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildConversationsList(false), // Chats
                      _buildConversationsList(true),  // Groups
                      const CallsScreen(),            // Calls
                      const SettingsScreen(),         // Settings
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // FABs
          if (_tabController.index != 3) // Hide FABs on Settings tab
            Positioned(
              right: 20,
              bottom: 120, // above bottom bar
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: 'ai_chat',
                    backgroundColor: accent,
                    onPressed: _openAiChat,
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Image.asset('assets/yapp_ai_avatar.png'),
                    ),
                  ),
                  if (_tabController.index == 0 || _tabController.index == 1) ...[
                    const SizedBox(height: 16),
                    FloatingActionButton(
                      heroTag: 'new_chat',
                      backgroundColor: accent.withValues(alpha: 0.8),
                      onPressed: _tabController.index == 0 ? _openNewChat : _openCreateGroup,
                      child: Icon(
                        _tabController.index == 0 ? Icons.chat_bubble_rounded : Icons.group_add_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ]
                ],
              ),
            ),
            
          // Bottom Navigation
          Align(
            alignment: Alignment.bottomCenter,
            child: GlassBottomBar(
              tabController: _tabController,
            ),
          ),
        ],
      ),
    );
  }
}
