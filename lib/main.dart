import 'dart:async';
import 'dart:io';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart'; // Ensure this import is present
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart'; // Add URL launcher for social media links

// Theme provider to handle theme changes across the app
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Color _accentColor = const Color(0xFFFCAA38); // Default amber/orange

  // Getters
  ThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;

  // Constructor loads saved preferences
  ThemeProvider() {
    _loadPreferences();
  }

  // Load saved preferences from SharedPreferences
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeString = prefs.getString('themeMode') ?? 'system';
    final accentColorValue = prefs.getInt('accentColor') ?? 0xFFFCAA38;

    _themeMode = _stringToThemeMode(themeModeString);
    _accentColor = Color(accentColorValue);
    notifyListeners();
  }

  // Convert string to ThemeMode
  ThemeMode _stringToThemeMode(String themeModeString) {
    switch (themeModeString) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  // Set theme mode and save to preferences
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode.toString().split('.').last);
    notifyListeners();
  }

  // Set accent color and save to preferences
  Future<void> setAccentColor(Color color) async {
    _accentColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accentColor', color.value);
    notifyListeners();
  }
}

// Add a helper class to handle navigation with animations
class AppNavigator {
  static Future<T?> push<T>(BuildContext context, Widget page, {String? routeName}) {
    return Navigator.push<T>(
      context,
      CupertinoPageRoute<T>(
        builder: (context) => page,
        settings: RouteSettings(name: routeName),
      ),
    );
  }

  static Future<T?> pushReplacement<T>(BuildContext context, Widget page, {String? routeName}) {
    return Navigator.pushReplacement(
      context,
      CupertinoPageRoute<T>(
        builder: (context) => page,
        settings: RouteSettings(name: routeName),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await FirebaseAppCheck.instance.activate();

  // Create ThemeProvider instance
  final themeProvider = ThemeProvider();

  runApp(
    ChangeNotifierProvider<ThemeProvider>.value(
      value: themeProvider,
      child: SyncAudioApp(),
    ),
  );
}

class SyncAudioApp extends StatelessWidget {
  const SyncAudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Yugly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: themeProvider.accentColor, // Use accent color from provider
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Poppins',
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: themeProvider.accentColor, // Use accent color from provider
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: themeProvider.accentColor, // Use accent color from provider
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: themeProvider.accentColor, // Use accent color from provider
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Poppins',
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: themeProvider.accentColor, // Use accent color from provider
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: themeProvider.accentColor, // Use accent color from provider
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
        ),
      ),
      themeMode: themeProvider.themeMode, // Use theme mode from provider
      home: AuthStateWrapper(),
    );
  }
}

class AuthStateWrapper extends StatefulWidget {
  const AuthStateWrapper({super.key});

  @override
  _AuthStateWrapperState createState() => _AuthStateWrapperState();
}

class _AuthStateWrapperState extends State<AuthStateWrapper> {
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

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }

      AppNavigator.pushReplacement(
        context,
        HomeScreen(),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Authentication failed: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credentials
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);

      // Make sure we save the user photo URL from Google account
      if (userCredential.user != null && userCredential.user!.photoURL != null) {
        debugPrint('Google sign-in successful with photo: ${userCredential.user!.photoURL}');
      } else {
        debugPrint('Google sign-in successful but no photo available');
      }

      AppNavigator.pushReplacement(
        context,
        HomeScreen(),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google Sign-In failed: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 20),
                    Icon(
                      Icons.headphones,
                      size: 80,
                      color: colorScheme.primary,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Yugly',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      'Listen together, anywhere',
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.secondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 48),
                    Text(
                      _isLogin ? 'Welcome Back' : 'Create Account',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 24),
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        contentPadding: EdgeInsets.symmetric(vertical: 16),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        contentPadding: EdgeInsets.symmetric(vertical: 16),
                      ),
                      obscureText: true,
                    ),
                    SizedBox(height: 24),
                    if (_isLoading)
                      Center(child: CircularProgressIndicator())
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton(
                            onPressed: _authenticate,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                            ),
                            child: Text(
                              _isLogin ? 'Login' : 'Sign Up',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SizedBox(height: 16),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _isLogin = !_isLogin;
                              });
                            },
                            child: Text(
                              _isLogin
                                  ? 'New user? Create an account'
                                  : 'Already have an account? Log in',
                            ),
                          ),
                          SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: Divider(thickness: 1),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'OR',
                                  style: TextStyle(
                                    color: colorScheme.secondary.withOpacity(0.7),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(thickness: 1),
                              ),
                            ],
                          ),
                          SizedBox(height: 24),
                          OutlinedButton.icon(
                            onPressed: _signInWithGoogle,
                            icon: Icon(Icons.login),
                            label: Text(
                              'Continue with Google',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: colorScheme.outline),
                              padding: EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Map<String, dynamic>> _listeningRooms = [];
  bool _isLoading = true;
  String _filterOption = 'all'; // Options: 'all', 'created', 'joined'
  // Add a RefreshController for the pull to refresh functionality
  final RefreshController _refreshController = RefreshController(initialRefresh: false);

  // Helper method to count active participants (those who haven't left)
  int _countActiveParticipants(Map participants) {
    int count = 0;
    participants.forEach((key, value) {
      bool hasLeft = false;
      if (value is Map && value.containsKey('hasLeft')) {
        hasLeft = value['hasLeft'] == true;
      }
      if (!hasLeft) {
        count++;
      }
    });
    return count;
  }

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'not-authenticated',
          message: 'User must be logged in to view rooms.',
        );
      }

      // Clear previous rooms
      _listeningRooms.clear();

      // Get all rooms
      final snapshot = await FirebaseDatabase.instance.ref('rooms').get();

      if (snapshot.exists) {
        Map<dynamic, dynamic> allRooms = snapshot.value as Map<dynamic, dynamic>;

        allRooms.forEach((roomId, roomData) {
          // Check if this user is a participant or creator based on filter
          bool isCreator = roomData['createdBy'] == user.uid;
          bool isParticipant = false;

          // Check if user is in participants list (including those who have left)
          if (roomData.containsKey('participants')) {
            var participants = roomData['participants'] as Map;
            if (participants.containsKey(user.uid)) {
              // Check if they've left the room
              bool hasLeft = false;
              if (participants[user.uid] is Map &&
                  participants[user.uid].containsKey('hasLeft') &&
                  participants[user.uid]['hasLeft'] == true) {
                hasLeft = true;
              }

              // Only consider them a participant if they haven't left
              isParticipant = !hasLeft;
            }
          }

          // Apply filter
          if (_filterOption == 'all' && (isCreator || isParticipant) ||
              _filterOption == 'created' && isCreator ||
              _filterOption == 'joined' && isParticipant && !isCreator) {

            Map<String, dynamic> room = {
              'id': roomId,
              'name': roomData['name'] ?? 'Unnamed Room',
              'isCreator': isCreator,
              'participantCount': roomData.containsKey('participants')
                  ? _countActiveParticipants(roomData['participants'] as Map)
                  : 0,
              'lastUpdated': roomData['lastUpdated'] ?? 0,
            };

            _listeningRooms.add(room);
          }
        });

        // Sort rooms by last updated (newest first)
        _listeningRooms.sort((a, b) => (b['lastUpdated'] as int).compareTo(a['lastUpdated'] as int));
      }

      setState(() {});
    } catch (e) {
      debugPrint('Error loading rooms: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load rooms. Please try again.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // If this was called from pull-to-refresh, we need to notify the controller
        _refreshController.refreshCompleted();
      }
    }
  }

  // Add a dedicated method for handling pull-to-refresh
  void _onRefresh() async {
    await _loadRooms();
  }

  Future<void> _createRoom() async {
    TextEditingController roomNameController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Create New Room'),
          content: TextField(
            controller: roomNameController,
            decoration: InputDecoration(
              hintText: 'Room Name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (roomNameController.text.trim().isNotEmpty) {
                  Navigator.of(context).pop();

                  try {
                    // Create the room in Firebase
                    String roomId = const Uuid().v4();
                    await FirebaseDatabase.instance.ref('rooms/$roomId').set({
                      'name': roomNameController.text,
                      'createdBy': FirebaseAuth.instance.currentUser!.uid,
                      'createdAt': DateTime.now().millisecondsSinceEpoch,
                      'isPlaying': false,
                      'currentPosition': 0,
                      'lastUpdated': DateTime.now().millisecondsSinceEpoch,
                      'participants': {
                        FirebaseAuth.instance.currentUser!.uid: true
                      }
                    });

                    // Navigate to the room
                    AppNavigator.push(
                      context,
                      ListeningRoomScreen(roomId: roomId),
                    ).then((_) => _loadRooms());
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to create room: ${e.toString()}'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                }
              },
              child: Text('Create'),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );
  }

  Future<void> _joinRoom() async {
    TextEditingController roomIdController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Join Room'),
          content: TextField(
            controller: roomIdController,
            decoration: InputDecoration(
              hintText: 'Enter Room ID',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final roomId = roomIdController.text.trim();
                if (roomId.isNotEmpty) {
                  Navigator.of(context).pop();

                  try {
                    // Store context in a local variable before async operations
                    final scaffoldMessenger = ScaffoldMessenger.of(context);

                    // Check if the room exists
                    final snapshot = await FirebaseDatabase.instance.ref('rooms/$roomId').get();

                    if (snapshot.exists) {
                      // Only navigate if the widget is still mounted
                      if (mounted) {
                        AppNavigator.push(
                          context,
                          ListeningRoomScreen(roomId: roomId),
                        ).then((_) => _loadRooms());
                      }
                    } else {
                      // Only show error if widget is still mounted
                      if (mounted) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(content: Text('Room not found. Please check the Room ID.')),
                        );
                      }
                    }
                  } catch (e) {
                    // Only show error if widget is still mounted
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to join room: ${e.toString()}')),
                      );
                    }
                  }
                }
              },
              child: Text('Join'),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final user = FirebaseAuth.instance.currentUser;

    // Get the user's display name and photo URL
    String displayName = user?.displayName ?? user?.email?.split('@')[0] ?? 'User';
    String? photoURL = user?.photoURL;
    String firstLetter = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

    Widget roomsList() {
      if (_isLoading) {
        return Center(child: CircularProgressIndicator());
      }

      // Wrap both empty state and ListView with SmartRefresher
      return SmartRefresher(
        controller: _refreshController,
        onRefresh: _onRefresh,
        header: WaterDropHeader(
          waterDropColor: colorScheme.primary,
          complete: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check, color: colorScheme.primary),
              SizedBox(width: 8),
              Text('Refreshed!', style: TextStyle(color: colorScheme.primary)),
            ],
          ),
        ),
        child: _listeningRooms.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.music_note_outlined,
                      size: 80,
                      color: colorScheme.primary.withOpacity(0.5),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No rooms found',
                      style: textTheme.titleLarge,
                    ),
                    SizedBox(height: 8),
                    Text(
                      _filterOption == 'all'
                          ? 'Create one to get started!'
                          : _filterOption == 'created'
                              ? 'You haven\'t created any rooms yet.'
                              : 'You haven\'t joined any rooms yet.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: _listeningRooms.length,
                padding: EdgeInsets.only(top: 8, bottom: 88),
                itemBuilder: (ctx, i) {
                  bool isCreator = _listeningRooms[i]['isCreator'] ?? false;

                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        AppNavigator.push(
                          context,
                          ListeningRoomScreen(
                            roomId: _listeningRooms[i]['id'],
                          ),
                        ).then((_) => _loadRooms());
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: isCreator
                                    ? colorScheme.primaryContainer
                                    : colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isCreator ? Icons.headphones : Icons.headset_mic,
                                color: isCreator
                                    ? colorScheme.primary
                                    : colorScheme.secondary,
                              ),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _listeningRooms[i]['name'] ?? 'Unnamed Room',
                                          style: textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isCreator)
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: colorScheme.primary,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            'Owner',
                                            style: TextStyle(
                                              color: colorScheme.onPrimary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '${_listeningRooms[i]['participantCount']} participants',
                                    style: textTheme.bodySmall,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'ID: ${_listeningRooms[i]['id'].toString().substring(0, 8)}...',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurface.withOpacity(0.5),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      );
    }

    return Scaffold(
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    themeProvider.accentColor,
                    themeProvider.accentColor.withBlue((themeProvider.accentColor.blue + 70) % 255),
                    themeProvider.accentColor.withRed((themeProvider.accentColor.red + 50) % 255),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              accountName: Text(
                displayName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              accountEmail: Text(user?.email ?? 'No email'),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                backgroundImage: photoURL != null ? NetworkImage(photoURL) : null,
                child: photoURL == null
                    ? Icon(
                        Icons.person,
                        size: 40,
                        color: themeProvider.accentColor,
                      )
                    : null,
              ),
            ),
            ListTile(
              leading: Icon(Icons.color_lens),
              title: Text('Theme Settings'),
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => ThemeSettingsSheet(),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('About'),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AboutDialog(
                    applicationName: 'Yugly',
                    applicationVersion: '1.0.0',
                    applicationIcon: Icon(
                      Icons.headphones,
                      size: 48,
                      color: themeProvider.accentColor,
                    ),
                    children: [
                      SizedBox(height: 16),
                      Text(
                        'Yugly is an audio sharing app that allows users to listen to audio together in real-time.',
                        style: TextStyle(fontSize: 14),
                      ),
                      SizedBox(height: 16),
                      // Social media icons in a row
                    ],
                  ),
                );
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.logout, color: Colors.red),
              title: Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                AppNavigator.pushReplacement(
                  context,
                  AuthScreen(),
                );
              },
            ),
            Expanded(child: Container()),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Made with ❤️ by Yugly',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: Text('Yugly'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: photoURL != null
              ? CircleAvatar(
                  backgroundImage: NetworkImage(photoURL),
                  radius: 16,
                )
              : CircleAvatar(
                  backgroundColor: colorScheme.primary,
                  radius: 16,
                  child: Text(
                    firstLetter,
                    style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.filter_list),
            tooltip: 'Filter Rooms',
            onSelected: (value) {
              setState(() {
                _filterOption = value;
              });
              _loadRooms();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'all',
                child: Row(
                  children: [
                    Icon(
                      Icons.all_inclusive,
                      color: _filterOption == 'all' ? colorScheme.primary : null,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'All Rooms',
                      style: TextStyle(
                        fontWeight: _filterOption == 'all' ? FontWeight.bold : null,
                        color: _filterOption == 'all' ? colorScheme.primary : null,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'created',
                child: Row(
                  children: [
                    Icon(
                      Icons.create,
                      color: _filterOption == 'created' ? colorScheme.primary : null,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Created by me',
                      style: TextStyle(
                        fontWeight: _filterOption == 'created' ? FontWeight.bold : null,
                        color: _filterOption == 'created' ? colorScheme.primary : null,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'joined',
                child: Row(
                  children: [
                    Icon(
                      Icons.group,
                      color: _filterOption == 'joined' ? colorScheme.primary : null,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Joined only',
                      style: TextStyle(
                        fontWeight: _filterOption == 'joined' ? FontWeight.bold : null,
                        color: _filterOption == 'joined' ? colorScheme.primary : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: roomsList(),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            onPressed: _createRoom,
            icon: Icon(Icons.add),
            label: Text('Create Room'),
            heroTag: 'createRoom',
          ),
          SizedBox(height: 16),
          FloatingActionButton.extended(
            onPressed: _joinRoom,
            icon: Icon(Icons.group_add),
            label: Text('Join Room'),
            heroTag: 'joinRoom',
            backgroundColor: colorScheme.secondaryContainer,
            foregroundColor: colorScheme.onSecondaryContainer,
          ),
        ],
      ),
    );
  }
}

class ListeningRoomScreen extends StatefulWidget {
  final String roomId;

  const ListeningRoomScreen({super.key, required this.roomId});

  @override
  _ListeningRoomScreenState createState() => _ListeningRoomScreenState();
}

class _ListeningRoomScreenState extends State<ListeningRoomScreen> with SingleTickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription? _playbackStateSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _roomSubscription;
  Timer? _syncTimer;

  String _roomName = 'Listening Room';
  String _audioTitle = 'No audio selected';
  bool _isOwner = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  bool _isSyncing = false;
  final List<String> _participants = [];
  final Map<String, Map<String, dynamic>> _participantDetails = {};
  bool _isPlaying = false;
  late AnimationController _animationController;

  // Add this state variable to track participant control permissions
  bool _participantsCanControl = false;

  // Add this field to track room members who have left
  bool _hasLeftRoom = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    _checkRoomOwnership();
    _initializeRoomListeners();
    _initializeAudioListeners();
  }

  Future<void> _checkRoomOwnership() async {
    final snapshot = await FirebaseDatabase.instance
        .ref('rooms/${widget.roomId}')
        .get();

    if (snapshot.exists) {
      Map<dynamic, dynamic> roomData = snapshot.value as Map<dynamic, dynamic>;
      setState(() {
        _isOwner = roomData['createdBy'] == FirebaseAuth.instance.currentUser!.uid;
        if (roomData.containsKey('audioTitle')) {
          _audioTitle = roomData['audioTitle'];
        }
      });

      // Join the room as a participant with user info
      final user = FirebaseAuth.instance.currentUser!;
      await FirebaseDatabase.instance
          .ref('rooms/${widget.roomId}/participants/${user.uid}')
          .set({
            'displayName': user.displayName ?? user.email?.split('@')[0] ?? 'Anonymous',
            'email': user.email,
            'photoURL': user.photoURL,
            'joinedAt': DateTime.now().millisecondsSinceEpoch,
          });

      // Auto-load audio when joining the room (for both host and participants)
      if (roomData.containsKey('audioUrl')) {
        // Load the audio automatically when entering the room
        _loadAudioFromUrl(roomData['audioUrl'].toString(), roomData['currentPosition'] ?? 0);
      }
    }
  }

  void _initializeRoomListeners() {
    // Listen for changes in the room data
    _roomSubscription = FirebaseDatabase.instance
        .ref('rooms/${widget.roomId}')
        .onValue
        .listen((event) {
      if (!event.snapshot.exists) {
        // Room was deleted
        Navigator.of(context).pop();
        return;
      }

      Map<dynamic, dynamic> roomData = event.snapshot.value as Map<dynamic, dynamic>;

      setState(() {
        if (roomData.containsKey('audioTitle')) {
          _audioTitle = roomData['audioTitle'];
        }
        if (roomData.containsKey('name')) {
          _roomName = roomData['name'];
        }

        // Update play state based on room data
        _isPlaying = roomData['isPlaying'] ?? false;

        // Check if participants can control playback
        _participantsCanControl = roomData['participantsCanControl'] ?? false;

        // Update participants list and details
        _participants.clear();
        _participantDetails.clear();
        if (roomData.containsKey('participants')) {
          Map<dynamic, dynamic> participantsData = roomData['participants'] as Map<dynamic, dynamic>;
          participantsData.forEach((key, value) {
            String uid = key.toString();

            // Only add participants who haven't left the room
            bool hasLeft = false;
            if (value is Map && value.containsKey('hasLeft')) {
              hasLeft = value['hasLeft'] == true;
            }

            // Only add the participant if they haven't left
            if (!hasLeft) {
              _participants.add(uid);

              // Store participant details if available
              if (value is Map) {
                _participantDetails[uid] = {
                  'displayName': value['displayName'] ?? 'Anonymous',
                  'email': value['email'],
                  'photoURL': value['photoURL'],
                  'joinedAt': value['joinedAt'],
                };
              }
            }
          });
        }
      });

      // Update animation state based on playback
      if (_isPlaying) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }

      // Handle playback state synchronization
      if (!_isOwner) {
        bool isPlaying = roomData['isPlaying'] ?? false;
        int position = roomData['currentPosition'] ?? 0;
        int lastUpdated = roomData['lastUpdated'] ?? 0;

        debugPrint('Room state update: isPlaying=$isPlaying, position=$position');

        // Calculate time drift since last update
        int now = DateTime.now().millisecondsSinceEpoch;
        int drift = now - lastUpdated;

        if (isPlaying) {
          // Adjust position for drift if playing
          position += drift;
        }

        // Sync playback immediately when state changes
        _syncPlayback(isPlaying, position);
      }
    });
  }

  void _initializeAudioListeners() {
    // Listen for audio player state changes
    _playbackStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (_isOwner) {
        // Update room state if we're the owner
        debugPrint('Owner playback state changed: playing=${state.playing}');
        FirebaseDatabase.instance.ref('rooms/${widget.roomId}').update({
          'isPlaying': state.playing,
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        });
      }

      setState(() {
        _isPlaying = state.playing;
      });

      if (state.playing) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });

    // For the owner, update position periodically
    if (_isOwner) {
      _syncTimer = Timer.periodic(Duration(seconds: 5), (_) {
        FirebaseDatabase.instance.ref('rooms/${widget.roomId}').update({
          'currentPosition': _audioPlayer.position.inMilliseconds,
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        });
      });
    }
    // For participants, check for sync issues periodically
    else {
      _syncTimer = Timer.periodic(Duration(seconds: 5), (_) async {
        try {
          final snapshot = await FirebaseDatabase.instance
              .ref('rooms/${widget.roomId}')
              .get();

          if (snapshot.exists) {
            Map<dynamic, dynamic> roomData = snapshot.value as Map<dynamic, dynamic>;
            bool isPlaying = roomData['isPlaying'] ?? false;
            int serverPosition = roomData['currentPosition'] ?? 0;
            int lastUpdated = roomData['lastUpdated'] ?? 0;

            // Calculate time drift since last update if playing
            int now = DateTime.now().millisecondsSinceEpoch;
            int drift = now - lastUpdated;

            if (isPlaying) {
              // Adjust position for drift if playing
              serverPosition += drift;
            }

            // Get local position
            final currentPosition = _audioPlayer.position.inMilliseconds;

            // Calculate difference
            final difference = (serverPosition - currentPosition).abs();

            // Only sync if difference is significant (more than 3 seconds)
            if (difference > 3000) {
              debugPrint('Significant sync difference detected: $difference ms. Syncing playback...');

              // Sync play state
              if (isPlaying != _audioPlayer.playing) {
                if (isPlaying) {
                  await _audioPlayer.play();
                } else {
                  await _audioPlayer.pause();
                }
              }

              // Sync position
              await _audioPlayer.seek(Duration(milliseconds: serverPosition));

              debugPrint('Sync completed. New position: ${_audioPlayer.position.inMilliseconds}');
            } else {
              // Just match play state without seeking
              if (isPlaying != _audioPlayer.playing) {
                if (isPlaying) {
                  await _audioPlayer.play();
                } else {
                  await _audioPlayer.pause();
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Error during periodic sync check: $e');
        }
      });
    }
  }

  // Helper method to load audio from URL and seek to position
  Future<void> _loadAudioFromUrl(String audioUrl, int position) async {
    try {
      debugPrint('Loading audio from URL: $audioUrl at position: $position');

      // Set the audio URL
      await _audioPlayer.setUrl(audioUrl);

      // Seek to the specified position
      if (position > 0) {
        await _audioPlayer.seek(Duration(milliseconds: position));
      }

      // Notify that audio was loaded successfully
      debugPrint('Audio loaded successfully at position: ${_audioPlayer.position}');
    } catch (e) {
      debugPrint('Error loading audio from URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading audio: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _syncPlayback(bool isPlaying, int position) async {
    setState(() {
      _isSyncing = true;
    });

    try {
      // Get current audio URL
      final snapshot = await FirebaseDatabase.instance
          .ref('rooms/${widget.roomId}/audioUrl')
          .get();

      if (snapshot.exists && snapshot.value != null) {
        String audioUrl = snapshot.value.toString();

        // Check if we need to load the audio (if it's not already loaded or if URL changed)
        if (_audioPlayer.audioSource == null ||
            (_audioPlayer.audioSource is UriAudioSource &&
            (_audioPlayer.audioSource as UriAudioSource).uri.toString() != audioUrl)) {
          await _audioPlayer.setUrl(audioUrl);
        }

        // Always seek to the synced position
        await _audioPlayer.seek(Duration(milliseconds: position));

        // Match the play state
        debugPrint('Syncing playback state: isPlaying=$isPlaying, position=$position');
        if (isPlaying && !_audioPlayer.playing) {
          await _audioPlayer.play();
        } else if (!isPlaying && _audioPlayer.playing) {
          await _audioPlayer.pause();
        }
      } else {
        // Don't show error message for newly created rooms that haven't had audio uploaded yet
        debugPrint('No audio URL found yet. This is normal for new rooms.');
      }
    } catch (e) {
      debugPrint('Sync playback error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  Future<String?> uploadFileWithRetry(File file) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        // Verify file existence
        if (!file.existsSync()) {
          throw Exception('File does not exist: ${file.path}');
        }

        // Create a reference with simpler path structure
        // Avoid unnecessary nesting that might cause permission issues
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${path.basename(file.path)}';
        Reference ref = FirebaseStorage.instance
            .ref()
            .child('audio_files')
            .child(fileName);

        debugPrint('Uploading to Firebase Storage path: ${ref.fullPath}');

        // Upload the file
        UploadTask uploadTask = ref.putFile(
          file,
          SettableMetadata(
            contentType: 'audio/mpeg', // Set appropriate content type
            customMetadata: {
              'roomId': widget.roomId,
              'uploadedBy': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
              'uploadedAt': DateTime.now().toString(),
            },
          ),
        );

        // Track upload progress
        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          if (mounted) {
            setState(() {
              _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
            });
          }
        });

        // Wait for the upload to complete
        final snapshot = await uploadTask.whenComplete(() => null);
        debugPrint('Upload completed, getting download URL...');

        // Get the download URL
        final audioUrl = await snapshot.ref.getDownloadURL();
        debugPrint('File uploaded successfully. Download URL: $audioUrl');

        return audioUrl; // Return the URL on success
      } catch (e) {
        retryCount++;
        debugPrint('Upload attempt $retryCount failed: $e');

        // Add delay before retry
        if (retryCount < maxRetries) {
          await Future.delayed(Duration(seconds: 2));
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Upload failed after $maxRetries attempts: ${e.toString()}'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
    return null; // Return null if upload fails
  }

  Future<void> _selectAndUploadAudio() async {
    if (!_isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Only the room owner can change the audio')),
      );
      return;
    }

    try {
      // Pick file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
      );

      if (result != null) {
        File file = File(result.files.single.path!);
        String fileName = path.basename(file.path);

        setState(() {
          _isUploading = true;
          _uploadProgress = 0.0;
          _audioTitle = fileName;
        });

        // Upload the file with retry logic
        final audioUrl = await uploadFileWithRetry(file);

        if (audioUrl != null) {
          // Update room data with new audio
          await FirebaseDatabase.instance.ref('rooms/${widget.roomId}').update({
            'audioUrl': audioUrl,
            'audioTitle': fileName,
            'currentPosition': 0,
            'isPlaying': false,
            'lastUpdated': DateTime.now().millisecondsSinceEpoch,
          });

          // Load the audio
          await _audioPlayer.setUrl(audioUrl);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Audio uploaded successfully')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload audio: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _loadExistingAudio() async {
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('rooms/${widget.roomId}/audioUrl')
          .get();

      if (snapshot.exists) {
        String audioUrl = snapshot.value.toString();
        debugPrint('Audio URL retrieved: $audioUrl');
        await _audioPlayer.setUrl(audioUrl);

        // If we're not the owner, sync to the room's current position
        if (!_isOwner) {
          final posSnapshot = await FirebaseDatabase.instance
              .ref('rooms/${widget.roomId}/currentPosition')
              .get();

          if (posSnapshot.exists) {
            int position = posSnapshot.value as int;
            await _audioPlayer.seek(Duration(milliseconds: position));
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Audio loaded successfully'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        debugPrint('No audio found at the specified reference.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No audio found in this room yet'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading audio: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load audio: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _leaveRoom() async {
    if (_hasLeftRoom) return; // Prevent multiple calls

    setState(() {
      _hasLeftRoom = true;
    });

    try {
      // Mark the user as having left the room first
      final userId = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseDatabase.instance
          .ref('rooms/${widget.roomId}/participants/$userId')
          .update({
            'hasLeft': true,
            'leftAt': DateTime.now().millisecondsSinceEpoch,
          });

      // Cancel subscriptions and clean up
      _playbackStateSubscription?.cancel();
      _positionSubscription?.cancel();
      _roomSubscription?.cancel();
      _syncTimer?.cancel();

      // Stop audio playback
      await _audioPlayer.stop();

      // Navigate back (if mounted)
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Error leaving room: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error leaving room: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );

        // Reset the state if there's an error
        setState(() {
          _hasLeftRoom = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // Don't call _leaveRoom() here as it can create issues with Navigator
    // Just make sure resources are properly disposed
    _playbackStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _roomSubscription?.cancel();
    _syncTimer?.cancel();
    _audioPlayer.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _copyRoomId(String roomId) {
    Clipboard.setData(ClipboardData(text: roomId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Room ID copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Add this method to toggle participant control permissions
  Future<void> _toggleParticipantControl() async {
    if (!_isOwner) return;

    setState(() {
      _participantsCanControl = !_participantsCanControl;
    });

    try {
      await FirebaseDatabase.instance
          .ref('rooms/${widget.roomId}')
          .update({
            'participantsCanControl': _participantsCanControl,
            'lastUpdated': DateTime.now().millisecondsSinceEpoch,
          });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_participantsCanControl
            ? 'Participants can now control playback'
            : 'Only you can control playback now'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('Error toggling participant control: $e');
      setState(() {
        _participantsCanControl = !_participantsCanControl; // Revert the change
      });
    }
  }

  Future<void> _shareRoom() async {
    try {
      // Generate invitation text with room ID
      String inviteText = "Join my Yugly listening room!\nRoom ID: ${widget.roomId}";

      // Use the native share dialog through share_plus package
      await Share.share(
        inviteText,
        subject: "Join Yugly Room",
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _showDeleteRoomDialog() async {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Delete Room'),
          content: Text('Are you sure you want to delete this room? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                // First close the dialog
                Navigator.of(context).pop();

                try {
                  // Clean up resources first
                  _playbackStateSubscription?.cancel();
                  _positionSubscription?.cancel();
                  _roomSubscription?.cancel();
                  _syncTimer?.cancel();
                  await _audioPlayer.stop();

                  // Delete the room from Firebase
                  await FirebaseDatabase.instance.ref('rooms/${widget.roomId}').remove();

                  // Navigate back to the home screen only after deletion is complete
                  if (mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Room deleted successfully'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to delete room: ${e.toString()}'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: Text('Delete'),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );
  }

  Widget _buildSlider() {
    return StreamBuilder<Duration>(
      stream: _audioPlayer.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = _audioPlayer.duration ?? Duration.zero;
        final colorScheme = Theme.of(context).colorScheme;

        // Ensure the slider value is within the valid range
        final maxDuration = duration.inMilliseconds.toDouble();
        final currentPosition = position.inMilliseconds.toDouble().clamp(0, maxDuration > 0 ? maxDuration : 1.0);

        return Column(
          children: [
            Slider(
              value: currentPosition.toDouble(),
              max: maxDuration > 0 ? maxDuration : 1.0, // Avoid division by zero
              activeColor: colorScheme.primary,
              inactiveColor: colorScheme.primary.withOpacity(0.3),
              onChanged: (_isOwner || _participantsCanControl) ? (value) {
                _audioPlayer.seek(Duration(milliseconds: value.toInt()));
              } : null,
              onChangeEnd: (_isOwner || _participantsCanControl) ? (value) {
                // Update Firebase for both owner and participants with control permission
                FirebaseDatabase.instance.ref('rooms/${widget.roomId}').update({
                  'currentPosition': value.toInt(),
                  'lastUpdated': DateTime.now().millisecondsSinceEpoch,
                });
              } : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(position),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_roomName),
        actions: [
          // New invite participants button
          IconButton(
            icon: Icon(Icons.person_add),
            onPressed: _shareRoom,
            tooltip: 'Invite Participants',
          ),
          // Replace individual actions with a popup menu
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'copy':
                  _copyRoomId(widget.roomId);
                  break;
                case 'leave':
                  _leaveRoom();
                  break;
                case 'delete':
                  if (_isOwner) {
                    _showDeleteRoomDialog();
                  }
                  break;
                case 'load':
                  _loadExistingAudio();
                  break;
              }
            },
            itemBuilder: (context) => [
              if (!_isOwner)
                PopupMenuItem(
                  value: 'leave',
                  child: Row(
                    children: [
                      Icon(Icons.exit_to_app),
                      SizedBox(width: 8),
                      Text('Leave Room'),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy),
                    SizedBox(width: 8),
                    Text('Copy Room ID'),
                  ],
                ),
              ),
              if (!_isOwner)
                PopupMenuItem(
                  value: 'load',
                  child: Row(
                    children: [
                      Icon(Icons.download),
                      SizedBox(width: 8),
                      Text('Load Audio'),
                    ],
                  ),
                ),
              if (_isOwner)
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete Room', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Now Playing Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.music_note,
                          color: colorScheme.primary,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Now Playing',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.audiotrack,
                              color: colorScheme.primary,
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              _audioTitle,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    if (_isUploading)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: _uploadProgress,
                            backgroundColor: colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Uploading: ${(_uploadProgress * 100).toStringAsFixed(0)}%',
                            style: textTheme.bodySmall,
                          ),
                        ],
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: _isOwner ? _selectAndUploadAudio : _loadExistingAudio,
                        icon: Icon(_isOwner ? Icons.upload_file : Icons.download),
                        label: Text(_isOwner ? 'Change Audio' : 'Load Audio'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          minimumSize: Size(double.infinity, 48),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 24),

            // Playback Controls
            Text(
              'Playback Controls',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(Icons.replay_10),
                          iconSize: 36,
                          color: colorScheme.primary,
                          onPressed: (_isOwner || _participantsCanControl) ? () async {
                            final position = _audioPlayer.position;
                            await _audioPlayer.seek(
                              position - Duration(seconds: 10),
                            );
                            // Update Firebase for both owner and participants with control permission
                            if (_isOwner || _participantsCanControl) {
                              await FirebaseDatabase.instance.ref('rooms/${widget.roomId}').update({
                                'currentPosition': _audioPlayer.position.inMilliseconds,
                                'lastUpdated': DateTime.now().millisecondsSinceEpoch,
                              });
                            }
                          } : null,
                        ),
                        SizedBox(width: 24),
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: AnimatedIcon(
                              icon: AnimatedIcons.play_pause,
                              progress: _animationController,
                              size: 36,
                              color: colorScheme.primary,
                            ),
                            iconSize: 36,
                            onPressed: (_isOwner || _participantsCanControl) ? () async {
                              // Only allow control if user is owner or has permission
                              try {
                                if (_audioPlayer.playing) {
                                  await _audioPlayer.pause();
                                  if (!_isOwner) {
                                    // If participant is controlling, update the room state directly
                                    await FirebaseDatabase.instance.ref('rooms/${widget.roomId}').update({
                                      'isPlaying': false,
                                      'currentPosition': _audioPlayer.position.inMilliseconds,
                                      'lastUpdated': DateTime.now().millisecondsSinceEpoch,
                                    });
                                  }
                                } else {
                                  await _audioPlayer.play();
                                  if (!_isOwner) {
                                    // If participant is controlling, update the room state directly
                                    await FirebaseDatabase.instance.ref('rooms/${widget.roomId}').update({
                                      'isPlaying': true,
                                      'currentPosition': _audioPlayer.position.inMilliseconds,
                                      'lastUpdated': DateTime.now().millisecondsSinceEpoch,
                                    });
                                  }
                                }
                              } catch (e) {
                                debugPrint('Error controlling playback: $e');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to control playback: ${e.toString()}')),
                                );
                              }
                            } : () {
                              // Show message when participants don't have permission
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Only the host can control playback'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(width: 24),
                        IconButton(
                          icon: Icon(Icons.forward_10),
                          iconSize: 36,
                          color: colorScheme.primary,
                          onPressed: (_isOwner || _participantsCanControl) ? () async {
                            final position = _audioPlayer.position;
                            await _audioPlayer.seek(
                              position + Duration(seconds: 10),
                            );
                            // Update Firebase for both owner and participants with control permission
                            if (_isOwner || _participantsCanControl) {
                              await FirebaseDatabase.instance.ref('rooms/${widget.roomId}').update({
                                'currentPosition': _audioPlayer.position.inMilliseconds,
                                'lastUpdated': DateTime.now().millisecondsSinceEpoch,
                              });
                            }
                          } : null,
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    _buildSlider(),
                  ],
                ),
              ),
            ),

            SizedBox(height: 24),

            // Participants Section
            Row(
              children: [
                Icon(
                  Icons.people,
                  color: colorScheme.primary,
                ),
                SizedBox(width: 8),
                Text(
                  'Participants (${_participants.length})',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Expanded(
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _participants.isEmpty
                    ? Center(
                        child: Text(
                          'No participants yet',
                          style: textTheme.bodyLarge,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _participants.length,
                        padding: EdgeInsets.all(8),
                        itemBuilder: (context, index) {
                          final participantId = _participants[index];
                          final isCurrentUser = participantId == FirebaseAuth.instance.currentUser!.uid;

                          // Get participant display name from details if available
                          String displayName = 'Anonymous';
                          if (_participantDetails.containsKey(participantId)) {
                            displayName = _participantDetails[participantId]!['displayName'] ?? 'Anonymous';
                          }

                          return Card(
                            elevation: 0,
                            color: isCurrentUser ? colorScheme.primaryContainer.withOpacity(0.5) : null,
                            margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isCurrentUser
                                    ? colorScheme.primary
                                    : colorScheme.secondary,
                                // Use profile picture if available from Google account
                                backgroundImage: _participantDetails.containsKey(participantId) &&
                                                _participantDetails[participantId]!['photoURL'] != null
                                    ? NetworkImage(_participantDetails[participantId]!['photoURL'])
                                    : null,
                                child: (_participantDetails.containsKey(participantId) &&
                                       _participantDetails[participantId]!['photoURL'] != null)
                                    ? null  // Don't show icon if we have a profile picture
                                    : Icon(
                                        Icons.person,
                                        color: isCurrentUser
                                            ? colorScheme.onPrimary
                                            : colorScheme.onSecondary,
                                        size: 20,
                                      ),
                              ),
                              title: Text(
                                displayName,
                                style: TextStyle(fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal),
                              ),
                              // subtitle: Text(
                              //   '${participantId.substring(0, 6)}...',
                              //   style: TextStyle(fontSize: 12),
                              // ),
                              trailing: isCurrentUser
                                  ? Chip(
                                      label: Text(
                                        'You',
                                        style: TextStyle(
                                          color: colorScheme.onPrimary,
                                          fontSize: 12,
                                        ),
                                      ),
                                      backgroundColor: colorScheme.primary,
                                      padding: EdgeInsets.zero,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
  }
}

class ThemeSettingsSheet extends StatelessWidget {
  const ThemeSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Define color options for accent colors
    final List<Color> accentColorOptions = [
      const Color(0xFFFCAA38), // Default amber/orange
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.purple,
      Colors.pink,
      Colors.teal,
      Colors.deepOrange,
      Colors.indigo,
    ];

    return Container(
      padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Appearance Settings',
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 24),

          // Theme Mode Selection
          Text(
            'Theme Mode',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ThemeModeCard(
                  title: 'Light',
                  icon: Icons.light_mode,
                  isSelected: themeProvider.themeMode == ThemeMode.light,
                  onTap: () => themeProvider.setThemeMode(ThemeMode.light),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _ThemeModeCard(
                  title: 'Dark',
                  icon: Icons.dark_mode,
                  isSelected: themeProvider.themeMode == ThemeMode.dark,
                  onTap: () => themeProvider.setThemeMode(ThemeMode.dark),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _ThemeModeCard(
                  title: 'System',
                  icon: Icons.brightness_auto,
                  isSelected: themeProvider.themeMode == ThemeMode.system,
                  onTap: () => themeProvider.setThemeMode(ThemeMode.system),
                ),
              ),
            ],
          ),

          SizedBox(height: 32),

          // Accent Color Selection
          Text(
            'Accent Color',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 16),

          // Color swatches
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: accentColorOptions.map((color) {
              return GestureDetector(
                onTap: () => themeProvider.setAccentColor(color),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: themeProvider.accentColor == color
                          ? colorScheme.primary
                          : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: themeProvider.accentColor == color
                      ? Icon(
                          Icons.check,
                          color: Colors.white,
                        )
                      : null,
                ),
              );
            }).toList(),
          ),

          SizedBox(height: 40),

          // Close button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Done',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Helper widget for theme mode selection cards
class _ThemeModeCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeModeCard({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outline.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              size: 32,
            ),
            SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person, size: 80),
          SizedBox(height: 24),
          Text(
            'Profile',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          Text(user?.email ?? 'No user logged in'),
          SizedBox(height: 24),
          ElevatedButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.of(context).pushReplacement(
                CupertinoPageRoute(builder: (context) => AuthScreen()),
              );
            },
            child: Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}