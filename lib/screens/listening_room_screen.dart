// ignore_for_file: unused_field

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';
import 'dart:io';

class ListeningRoomScreen extends StatefulWidget {
  final String roomId;

  const ListeningRoomScreen({super.key, required this.roomId});

  @override
  ListeningRoomScreenState createState() => ListeningRoomScreenState();
}

class ListeningRoomScreenState extends State<ListeningRoomScreen> with SingleTickerProviderStateMixin {
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
  // Future<void> _toggleParticipantControl() async {
  //   if (!_isOwner) return;

  //   setState(() {
  //     _participantsCanControl = !_participantsCanControl;
  //   });

  //   try {
  //     await FirebaseDatabase.instance
  //         .ref('rooms/${widget.roomId}')
  //         .update({
  //           'participantsCanControl': _participantsCanControl,
  //           'lastUpdated': DateTime.now().millisecondsSinceEpoch,
  //         });

  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text(_participantsCanControl
  //           ? 'Participants can now control playback'
  //           : 'Only you can control playback now'),
  //         behavior: SnackBarBehavior.floating,
  //       ),
  //     );
  //   } catch (e) {
  //     debugPrint('Error toggling participant control: $e');
  //     setState(() {
  //       _participantsCanControl = !_participantsCanControl; // Revert the change
  //     });
  //   }
  // }

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