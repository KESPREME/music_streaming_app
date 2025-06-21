// import 'package:firebase_auth/firebase_auth.dart' as fb_auth; // Aliased to avoid conflict - Commented out
import 'package:flutter/foundation.dart';
import '../models/user_model.dart'; // Your UserModel
import './firestore_service.dart'; // To create user profile in Firestore

// Placeholder for fb_auth.User and fb_auth.FirebaseAuthException
class MockFirebaseUser {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoURL;
  MockFirebaseUser({required this.uid, this.email, this.displayName, this.photoURL});
  Future<void> updateDisplayName(String? name) async {}
}

class MockFirebaseAuthException implements Exception {
  final String? message;
  final String? code;
  MockFirebaseAuthException({this.message, this.code});
  @override
  String toString() => "MockFirebaseAuthException: $message (code: $code)";
}


class AuthService {
  // final fb_auth.FirebaseAuth _firebaseAuth = fb_auth.FirebaseAuth.instance; // Commented out
  final FirestoreService _firestoreService = FirestoreService();

  // Stream of authentication state changes
  Stream<UserModel?> get user {
    // return _firebaseAuth.authStateChanges().asyncMap((fb_auth.User? firebaseUser) async { // Commented out
    return Stream.value(null).asyncMap((MockFirebaseUser? firebaseUser) async { // Placeholder stream
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

  // fb_auth.User? get currentFirebaseUser => _firebaseAuth.currentUser; // Commented out
  MockFirebaseUser? get currentFirebaseUser { // Placeholder
    // Simulate a logged-in user for testing social features if needed
    // return MockFirebaseUser(uid: "mockUserId", name: "Mock User", email: "mock@example.com");
    return null; // Default to no user
  }


  Future<UserModel?> signInWithEmailAndPassword(String email, String password) async {
    try {
      // final fb_auth.UserCredential userCredential = await _firebaseAuth.signInWithEmailAndPassword( // Commented out
      //   email: email,
      //   password: password,
      // );
      // Simulate successful sign-in for now
      await Future.delayed(Duration(milliseconds: 500)); // Simulate network delay
      final mockUser = MockFirebaseUser(uid: "mock-${email.hashCode}", email: email, displayName: email.split('@').first);
      // if (userCredential.user != null) { // Commented out
      if (mockUser != null) { // Using mockUser
        // Fetch or return UserModel
        UserModel? userModel = await _firestoreService.getUser(mockUser.uid);
        // if (userModel == null && userCredential.user!.displayName != null) { // Commented out
        if (userModel == null && mockUser.displayName != null) { // Using mockUser
            // This case might happen if Firestore profile creation failed previously
            // Or if this is a very old account prior to Firestore profile creation.
            // Create a basic profile now.
            print("User signed in, but no Firestore profile found. Creating one.");
            final newUser = UserModel(
                id: mockUser.uid,
                name: mockUser.displayName ?? email.split('@').first, // Default name
                avatarUrl: mockUser.photoURL,
            );
            await _firestoreService.createUser(newUser);
            return newUser;
        }
        return userModel;
      }
      return null;
    // } on fb_auth.FirebaseAuthException catch (e) { // Commented out
    } on MockFirebaseAuthException catch (e) { // Using mock exception
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
      // final fb_auth.UserCredential userCredential = await _firebaseAuth.createUserWithEmailAndPassword( // Commented out
      //   email: email,
      //   password: password,
      // );
      await Future.delayed(Duration(milliseconds: 500)); // Simulate network delay
      final mockUser = MockFirebaseUser(uid: "mock-${email.hashCode}-new", email: email, displayName: name);


      // if (userCredential.user != null) { // Commented out
      if (mockUser != null) { // Using mockUser
        // Update Firebase user's display name
        // await userCredential.user!.updateDisplayName(name); // Commented out
        await mockUser.updateDisplayName(name); // Using mockUser

        // Create UserModel and save to Firestore
        final newUser = UserModel(
          id: mockUser.uid,
          name: name,
          // avatarUrl: null, // Set a default or allow user to upload later
        );
        await _firestoreService.createUser(newUser);
        return newUser;
      }
      return null;
    // } on fb_auth.FirebaseAuthException catch (e) { // Commented out
    } on MockFirebaseAuthException catch (e) { // Using mock exception
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
      // await _firebaseAuth.signOut(); // Commented out
      await Future.delayed(Duration(milliseconds: 100)); // Simulate sign out
      print("Mock user signed out.");
    } catch (e) {
      if (kDebugMode) {
        print("Error signing out: $e");
      }
      // Optionally, rethrow or handle as needed, but sign out should generally succeed locally.
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      // await _firebaseAuth.sendPasswordResetEmail(email: email); // Commented out
      await Future.delayed(Duration(milliseconds: 300)); // Simulate email sending
      print("Mock password reset email sent to $email");
    // } on fb_auth.FirebaseAuthException catch (e) { // Commented out
    } on MockFirebaseAuthException catch (e) { // Using mock exception
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
