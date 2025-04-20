import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:yugly/screens/auth_screen.dart';
import 'package:yugly/screens/home_screen.dart';

class AuthStateWrapper extends StatefulWidget {
  const AuthStateWrapper({super.key});

  @override
  AuthStateWrapperState createState() => AuthStateWrapperState();
}

class AuthStateWrapperState extends State<AuthStateWrapper> {
  late StreamSubscription<User?> _authStateSubscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Listen to auth state changes and update accordingly
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      setState(() {
        _isLoading = false;
      });
    });
  }

  @override
  void dispose() {
    _authStateSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Show loading spinner while checking auth state
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.headphones,
                size: 80,
                color: colorScheme.primary,
              ),
              SizedBox(height: 24),
              Text(
                'Yugly',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              SizedBox(height: 36),
              CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }

    // Check if user is signed in
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // User is signed in, go to home screen
      return HomeScreen();
    } else {
      // User is not signed in, go to auth screen
      return AuthScreen();
    }
  }
}