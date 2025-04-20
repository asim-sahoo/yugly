import 'package:flutter/material.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:yugly/utils/navigator.dart';
import 'package:yugly/providers/theme_provider.dart';
import 'auth_screen.dart';
import 'listening_room_screen.dart';
import 'package:yugly/widgets/theme_settings.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
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