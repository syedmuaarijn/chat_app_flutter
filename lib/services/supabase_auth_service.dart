import 'dart:io';
import 'package:chat_app_flutter/models/user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthService {
  final SupabaseClient _supabaseClient = Supabase.instance.client;

  String? get currentUserId => _supabaseClient.auth.currentUser?.id;
  User? get currentUser => _supabaseClient.auth.currentUser;
  bool get isLoggedin => _supabaseClient.auth.currentUser != null;

  // Future<AuthResponse> signInWithEmailAndPassword(
  //   String email,
  //   String password,
  // ) async {
  //   return await _supabaseClient.auth.signInWithPassword(
  //     email: email,
  //     password: password,
  //   );
  // }

  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final AuthResponse response = await _supabaseClient.auth
          .signInWithPassword(email: email, password: password);
      if (response.user == null) {
        throw Exception('Sign In Failed');
      }
      final profileData = await _supabaseClient
          .from('profiles')
          .select()
          .eq('id', response.user!.id)
          .single();
      return UserModel.fromJson(profileData);
    } on AuthException catch (e) {
      throw Exception('Sign in Failed: ${e.message}');
    } catch (e) {
      throw Exception('Sign in Failed: $e');
    }
  }

  // Future<AuthResponse> signUpWithEmailAndPassword(
  //   String email,
  //   String password,
  // ) async {
  //   return await _supabaseClient.auth.signUp(email: email, password: password);
  // }

  Future<UserModel> signUp({
    required String email,
    required String password,
    required String username,
    String? fullName,
  }) async {
    try {
      final AuthResponse response = await _supabaseClient.auth.signUp(
        email: email,
        password: password,
        data: {'username': username, 'full_name': fullName ?? ''},
      );
      if (response.user == null) {
        throw Exception('Signup failed');
      }

      final userId = response.user!.id;
      final now = DateTime.now().toIso8601String();

      // Upsert the profile row in case the DB trigger hasn't created it yet.
      // If it already exists this is a no-op.
      await _supabaseClient.from('profiles').upsert({
        'id': userId,
        'username': username,
        'full_name': fullName ?? '',
        'avatar_url': '',
        'bio': '',
        'created_at': now,
        'updated_at': now,
      });

      final profileData = await _supabaseClient
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      return UserModel.fromJson(profileData);
    } on AuthException catch (e) {
      throw Exception('Signup Failed: ${e.message}');
    } catch (e) {
      throw Exception('Signup Failed: $e');
    }
  }

  Future<void> signOut() async {
    try {
      await _supabaseClient.auth.signOut();
    } catch (e) {
      throw Exception('Sign out Failed: $e');
    }
  }

  // Future<void> sendPasswordResetEmail(String email) async {
  //   await _supabaseClient.auth.resetPasswordForEmail(
  //     email,
  //     redirectTo: 'myapp://reset-password',
  //   );
  // }

  // Future<UserResponse> updatePassword(String newPassword) async {
  //   return await _supabaseClient.auth.updateUser(
  //     UserAttributes(password: newPassword),
  //   );
  // }

  Future<String> uploadAvatar(File file) async {
    try {
      final userId = currentUserId;
      if (userId == null) throw Exception('No user logged in');

      final fileExt = file.path.split('.').last;
      final storagePath = 'user_avatars/${userId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await _supabaseClient.storage
          .from('avatars')
          .upload(
            storagePath,
            file,
            fileOptions: const FileOptions(cacheControl: '0', upsert: true),
          );

      final publicUrl = _supabaseClient.storage
          .from('avatars')
          .getPublicUrl(storagePath);

      return publicUrl;
    } on StorageException catch (e) {
      if (e.message.contains('Bucket not found') || e.statusCode == 404) {
        throw Exception(
          'Storage bucket "avatars" not found. Please create this bucket in your Supabase dashboard at: https://supabase.com/dashboard/project/nfjlgqylmggppsxabtbd/storage',
        );
      }
      throw Exception('Failed to upload profile picture: ${e.message}');
    } catch (e) {
      throw Exception('Failed to upload profile picture: $e');
    }
  }

  Future<UserModel?> getCurrentUserProfile() async {
    try {
      final userId = currentUserId;
      if (userId == null) {
        return null;
      }
      final profileData = await _supabaseClient
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      return UserModel.fromJson(profileData);
    } catch (e) {
      throw Exception('Failed to fetch user Profile');
    }
  }

  Future<UserModel> updateProfile({
    String? username,
    String? fullName,
    String? bio,
    String? avatarUrl,
  }) async {
    try {
      final userId = currentUserId;
      if (userId == null) {
        throw Exception('No authenticated user');
      }
      // ignore: use_null_aware_elements
      final updates = {
        if (username != null) 'username': username, // ignore: use_null_aware_elements
        if (fullName != null) 'full_name': fullName, // ignore: use_null_aware_elements
        if (bio != null) 'bio': bio, // ignore: use_null_aware_elements
        if (avatarUrl != null) 'avatar_url': avatarUrl, // ignore: use_null_aware_elements
        'updated_at': DateTime.now().toIso8601String(),
      };

      final profileData = await _supabaseClient
          .from('profiles')
          .update(updates)
          .eq('id', userId)
          .select()
          .single();

      return UserModel.fromJson(profileData);
    } catch (e) {
      throw Exception('Failed to update Profile: $e');
    }
  }

  Future<void> updateUserPassword(String newPassword) async {
    try {
      await _supabaseClient.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } on AuthException catch (e) {
      throw Exception('Failed to update password: ${e.message}');
    } catch (e) {
      throw Exception('Failed to update password: $e');
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _supabaseClient.auth.resetPasswordForEmail(email);
    } on AuthException catch (e) {
      throw Exception('Failed to send password reset email ${e.message}');
    } catch (e) {
      throw Exception('Failed to send password reset email: $e');
    }
  }

  Stream<AuthState> get authStateChanges =>
      _supabaseClient.auth.onAuthStateChange;
}
