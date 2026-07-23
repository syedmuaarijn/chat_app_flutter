import 'dart:io';
import 'package:chat_app_flutter/services/supabase_auth_service.dart';
import 'package:chat_app_flutter/services/local_cache_service.dart';
import 'package:chat_app_flutter/services/offline_service.dart';
import 'package:flutter/material.dart';
import 'package:chat_app_flutter/models/user_model.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthProvider with ChangeNotifier {
  final SupabaseAuthService _authService = SupabaseAuthService();
  final LocalCacheService _cacheService = LocalCacheService();
  final OfflineService _offlineService = OfflineService();
  
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _error;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;

  AuthProvider() {
    _initAuth();
  }

  Future<void> _initAuth() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _cacheService.initialize();
      await _offlineService.initialize();
      
      // Try to restore session from cache first (highest priority)
      final session = _cacheService.getSession();
      final accessToken = session['access_token'];
      final refreshToken = session['refresh_token'];
      final hasSession = accessToken != null;
      
      if (hasSession) {
        // Restore the Supabase SDK session from stored tokens BEFORE any
        // isLoggedin check.  On cold boot offline, Supabase.currentUser is
        // null until setSession() has been called — this ensures the SDK
        // state is consistent even when there is no network.
        try {
          await Supabase.instance.client.auth
              .setSession(refreshToken ?? '', accessToken: accessToken)
              .timeout(
                const Duration(seconds: 5),
                onTimeout: () => throw Exception('setSession timed out'),
              );
        } catch (e) {
          // Expired/invalid token or network timeout — fall through gracefully.
          // The user will still be restored from cache below.
          debugPrint('setSession failed (token may be expired or timed out): $e');
        }

        // Load user from cache immediately (works offline)
        _currentUser = await _loadUserFromCache();
        
        // If online, try to refresh from server and update cache
        if (await _offlineService.hasConnection()) {
          try {
            if (_authService.isLoggedin) {
              final freshUser = await _authService.getCurrentUserProfile();
              _currentUser = freshUser;
              await _cacheCurrentUser();
              
              // Update cached session with fresh tokens
              final currentSession = Supabase.instance.client.auth.currentSession;
              if (currentSession != null) {
                await _cacheService.saveSession(
                  currentSession.accessToken,
                  currentSession.refreshToken ?? '',
                );
              }
            }
          } catch (e) {
            // If server fetch fails, keep using cached user (already loaded above)
            debugPrint('Failed to refresh user from server, using cached: $e');
          }
        }
      } else {
        // No cached session, check if Supabase has a session
        if (_authService.isLoggedin) {
          try {
            _currentUser = await _authService.getCurrentUserProfile();
            await _cacheCurrentUser();
            
            // Cache the session
            final currentSession = Supabase.instance.client.auth.currentSession;
            if (currentSession != null) {
              await _cacheService.saveSession(
                currentSession.accessToken,
                currentSession.refreshToken ?? '',
              );
            }
          } catch (e) {
            _error = e.toString();
          }
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<UserModel?> _loadUserFromCache() async {
    try {
      // Guard: ensure chatCache box is open before accessing it.
      // If the box is not yet open (e.g., called from an unexpected code path
      // before initialize() has completed), return null defensively.
      if (!Hive.isBoxOpen('chatCache')) {
        debugPrint('_loadUserFromCache: chatCache box not open, skipping.');
        return null;
      }
      // Try to get cached user data
      final cachedUserData = _cacheService.chatCache.get('current_user');
      if (cachedUserData != null && cachedUserData is Map) {
        // Use deepConvert to recursively convert all nested Map<dynamic,dynamic>
        // that Hive returns, preventing _CastError in UserModel.fromJson.
        return UserModel.fromJson(
          LocalCacheService.deepConvert(cachedUserData) as Map<String, dynamic>,
        );
      }
    } catch (e) {
      debugPrint('Error loading user from cache: $e');
    }
    return null;
  }

  Future<void> _cacheCurrentUser() async {
    if (_currentUser != null) {
      try {
        await _cacheService.chatCache.put('current_user', _currentUser!.toJson());
      } catch (e) {
        debugPrint('Error caching user: $e');
      }
    }
  }

  Future<bool> signIn({required String email, required String password}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentUser = await _authService.signIn(
        email: email,
        password: password,
      );
      
      // Save session to cache
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        await _cacheService.saveSession(
          session.accessToken,
          session.refreshToken ?? '',
        );
      }
      
      await _cacheCurrentUser();
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String username,
    String? fullName,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentUser = await _authService.signUp(
        email: email,
        password: password,
        username: username,
        fullName: fullName,
      );
      
      // Save session to cache
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        await _cacheService.saveSession(
          session.accessToken,
          session.refreshToken ?? '',
        );
      }
      
      await _cacheCurrentUser();
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _cacheService.clearSession();
      await _authService.signOut();
      _currentUser = null;
      // Note: We don't clearCache() here to preserve chat data for offline access
      // Cache will be managed by age-based cleanup
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String> uploadAvatar(File file) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final url = await _authService.uploadAvatar(file);
      _isLoading = false;
      notifyListeners();
      return url;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<bool> updateProfile({
    String? username,
    String? fullName,
    String? bio,
    String? avatarUrl,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (_currentUser == null) {
        throw Exception('No user is currently signed in.');
      }

      final updatedUser = await _authService.updateProfile(
        username: username,
        fullName: fullName,
        bio: bio,
        avatarUrl: avatarUrl,
      );

      _currentUser = updatedUser;
      await _cacheCurrentUser();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetPassword(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _authService.resetPassword(email);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshUser() async {
    try {
      _currentUser = await _authService.getCurrentUserProfile();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
