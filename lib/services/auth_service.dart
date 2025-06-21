import 'package:firebase_auth/firebase_auth.dart' as fb_auth; // Aliased to avoid conflict
import 'package:flutter/foundation.dart';
import '../models/user_model.dart'; // Your UserModel
import './firestore_service.dart'; // To create user profile in Firestore

class AuthService {
  final fb_auth.FirebaseAuth _firebaseAuth = fb_auth.FirebaseAuth.instance;
  final FirestoreService _firestoreService = FirestoreService();

  // Stream of authentication state changes
  Stream<UserModel?> get user {
    return _firebaseAuth.authStateChanges().asyncMap((fb_auth.User? firebaseUser) async {
      if (firebaseUser == null) {
        return null;
      }
      // Fetch additional user details from Firestore
      UserModel? firestoreUser = await _firestoreService.getUser(firebaseUser.uid);
      if (firestoreUser != null) {
        return firestoreUser;
      }
      // If user exists in Firebase Auth but not Firestore (e.g. old account, error during signup)
      // Create a basic UserModel. Ideally, this case is handled more gracefully during signup.
      return UserModel(id: firebaseUser.uid, name: firebaseUser.displayName ?? firebaseUser.email ?? "User");
    });
  }

  fb_auth.User? get currentFirebaseUser => _firebaseAuth.currentUser;


  Future<UserModel?> signInWithEmailAndPassword(String email, String password) async {
    try {
      final fb_auth.UserCredential userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (userCredential.user != null) {
        // Fetch or return UserModel
        UserModel? userModel = await _firestoreService.getUser(userCredential.user!.uid);
        if (userModel == null && userCredential.user!.displayName != null) {
            // This case might happen if Firestore profile creation failed previously
            // Or if this is a very old account prior to Firestore profile creation.
            // Create a basic profile now.
            print("User signed in, but no Firestore profile found. Creating one.");
            final newUser = UserModel(
                id: userCredential.user!.uid,
                name: userCredential.user!.displayName ?? email.split('@').first, // Default name
                avatarUrl: userCredential.user!.photoURL,
            );
            await _firestoreService.createUser(newUser);
            return newUser;
        }
        return userModel;
      }
      return null;
    } on fb_auth.FirebaseAuthException catch (e) {
      if (kDebugMode) {
        print("Firebase Auth Exception on sign in: ${e.message} (Code: ${e.code})");
      }
      throw Exception(e.message ?? "Sign in failed."); // Provide user-friendly message
    } catch (e) {
      if (kDebugMode) {
        print("General Exception on sign in: $e");
      }
      throw Exception("An unexpected error occurred during sign in.");
    }
  }

  Future<UserModel?> signUpWithEmailAndPassword(String name, String email, String password) async {
    try {
      final fb_auth.UserCredential userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        // Update Firebase user's display name
        await userCredential.user!.updateDisplayName(name);

        // Create UserModel and save to Firestore
        final newUser = UserModel(
          id: userCredential.user!.uid,
          name: name,
          // avatarUrl: null, // Set a default or allow user to upload later
        );
        await _firestoreService.createUser(newUser);
        return newUser;
      }
      return null;
    } on fb_auth.FirebaseAuthException catch (e) {
      if (kDebugMode) {
        print("Firebase Auth Exception on sign up: ${e.message} (Code: ${e.code})");
      }
      throw Exception(e.message ?? "Sign up failed.");
    } catch (e) {
      if (kDebugMode) {
        print("General Exception on sign up: $e");
      }
      throw Exception("An unexpected error occurred during sign up.");
    }
  }

  Future<void> signOut() async {
    try {
      await _firebaseAuth.signOut();
    } catch (e) {
      if (kDebugMode) {
        print("Error signing out: $e");
      }
      // Optionally, rethrow or handle as needed, but sign out should generally succeed locally.
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
    } on fb_auth.FirebaseAuthException catch (e) {
       if (kDebugMode) {
        print("Firebase Auth Exception on password reset: ${e.message} (Code: ${e.code})");
      }
      throw Exception(e.message ?? "Password reset failed.");
    }
    catch (e) {
       if (kDebugMode) {
        print("General Exception on password reset: $e");
      }
      throw Exception("An unexpected error occurred during password reset.");
    }
  }

  // Add other auth methods as needed (e.g., Google Sign-In, Apple Sign-In)
}
