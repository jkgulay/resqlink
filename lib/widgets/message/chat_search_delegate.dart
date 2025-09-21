import 'package:flutter/material.dart';
import '../../models/message_model.dart';
import '../../models/chat_session_model.dart';
import '../../services/database_service.dart';
import '../../utils/resqlink_theme.dart';

class ChatSearchDelegate extends SearchDelegate<MessageModel?> {
  final String? sessionId;

  ChatSearchDelegate({this.sessionId});

  @override
  ThemeData appBarTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: ResQLinkTheme.cardDark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white60),
        border: InputBorder.none,
      ),
      textTheme: TextTheme(
        titleLarge: TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }

  @override
  String get searchFieldLabel => 'Search messages...';

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: Icon(Icons.clear),
        onPressed: () {
          query = '';
          showSuggestions(context);
        },
      ),
      PopupMenuButton<String>(
        icon: Icon(Icons.filter_list),
        color: ResQLinkTheme.cardDark,
        onSelected: (value) {
          _applyFilter(context, value);
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'emergency',
            child: Row(
              children: [
                Icon(Icons.warning, color: ResQLinkTheme.primaryRed, size: 20),
                SizedBox(width: 8),
                Text('Emergency messages', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'location',
            child: Row(
              children: [
                Icon(Icons.location_on, color: Colors.blue, size: 20),
                SizedBox(width: 8),
                Text('Location messages', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'today',
            child: Row(
              children: [
                Icon(Icons.today, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text('Today\'s messages', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'week',
            child: Row(
              children: [
                Icon(Icons.date_range, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Text('This week', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return _buildRecentSearches(context);
    }
    return _buildSearchResults(context);
  }

  Widget _buildSearchResults(BuildContext context) {
    return Container(
      color: ResQLinkTheme.backgroundDark,
      child: FutureBuilder<List<MessageModel>>(
        future: _searchMessages(query),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                color: ResQLinkTheme.primaryRed,
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.white60, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'Error searching messages',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            );
          }

          final messages = snapshot.data ?? [];

          if (messages.isEmpty) {
            return _buildNoResults(context);
          }

          return ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              return _buildMessageSearchResult(context, message);
            },
          );
        },
      ),
    );
  }

  Widget _buildNoResults(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            color: Colors.white30,
            size: 64,
          ),
          SizedBox(height: 16),
          Text(
            'No messages found',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            query.isNotEmpty
                ? 'Try searching with different keywords'
                : 'Start typing to search messages',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSearches(BuildContext context) {
    // This could be enhanced to show actual recent searches from shared preferences
    return Container(
      color: ResQLinkTheme.backgroundDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Search suggestions',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _buildSuggestionTile(context, 'emergency', Icons.warning, 'Emergency messages'),
          _buildSuggestionTile(context, 'location', Icons.location_on, 'Location messages'),
          _buildSuggestionTile(context, 'SOS', Icons.sos, 'SOS alerts'),
          _buildSuggestionTile(context, 'help', Icons.help_outline, 'Help requests'),
        ],
      ),
    );
  }

  Widget _buildSuggestionTile(
    BuildContext context,
    String suggestion,
    IconData icon,
    String description,
  ) {
    return ListTile(
      leading: Icon(icon, color: Colors.white60),
      title: Text(suggestion, style: TextStyle(color: Colors.white)),
      subtitle: Text(description, style: TextStyle(color: Colors.white60)),
      onTap: () {
        query = suggestion;
        showResults(context);
      },
    );
  }

  Widget _buildMessageSearchResult(BuildContext context, MessageModel message) {
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      color: ResQLinkTheme.cardDark,
      child: InkWell(
        onTap: () => close(context, message),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildMessageTypeIcon(message),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message.fromUser,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    _formatTimestamp(message.dateTime),
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              RichText(
                text: _buildHighlightedText(message.message, query),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (message.hasLocation) ...[
                SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.blue, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Location: ${message.latitude!.toStringAsFixed(4)}, ${message.longitude!.toStringAsFixed(4)}',
                      style: TextStyle(color: Colors.blue, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageTypeIcon(MessageModel message) {
    IconData icon;
    Color color;

    switch (message.messageType) {
      case MessageType.emergency:
      case MessageType.sos:
        icon = Icons.warning;
        color = ResQLinkTheme.primaryRed;
      case MessageType.location:
        icon = Icons.location_on;
        color = Colors.blue;
      case MessageType.file:
        icon = Icons.attach_file;
        color = Colors.purple;
      case MessageType.system:
        icon = Icons.info;
        color = Colors.grey;
      default:
        icon = Icons.message;
        color = Colors.white60;
    }

    return Icon(icon, color: color, size: 20);
  }

  TextSpan _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return TextSpan(
        text: text,
        style: TextStyle(color: Colors.white70),
      );
    }

    final List<TextSpan> spans = [];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();

    int start = 0;
    int index = lowerText.indexOf(lowerQuery);

    while (index != -1) {
      // Add text before match
      if (index > start) {
        spans.add(TextSpan(
          text: text.substring(start, index),
          style: TextStyle(color: Colors.white70),
        ));
      }

      // Add highlighted match
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: TextStyle(
          color: ResQLinkTheme.primaryRed,
          fontWeight: FontWeight.bold,
          backgroundColor: ResQLinkTheme.primaryRed.withOpacity(0.2),
        ),
      ));

      start = index + query.length;
      index = lowerText.indexOf(lowerQuery, start);
    }

    // Add remaining text
    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: TextStyle(color: Colors.white70),
      ));
    }

    return TextSpan(children: spans);
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  Future<List<MessageModel>> _searchMessages(String searchQuery) async {
    if (searchQuery.isEmpty) return [];

    try {
      List<MessageModel> messages;

      if (sessionId != null) {
        // Search within specific chat session
        messages = await DatabaseService.getChatSessionMessages(sessionId!);
      } else {
        // Search all messages
        messages = await DatabaseService.getAllMessages();
      }

      // Filter messages based on search query
      final filteredMessages = messages.where((message) {
        final lowerQuery = searchQuery.toLowerCase();
        return message.message.toLowerCase().contains(lowerQuery) ||
               message.fromUser.toLowerCase().contains(lowerQuery) ||
               message.type.toLowerCase().contains(lowerQuery);
      }).toList();

      // Sort by timestamp (newest first)
      filteredMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return filteredMessages;
    } catch (e) {
      debugPrint('❌ Error searching messages: $e');
      return [];
    }
  }

  void _applyFilter(BuildContext context, String filter) {
    switch (filter) {
      case 'emergency':
        query = 'emergency';
      case 'location':
        query = 'location';
      case 'today':
        // This would need custom implementation to filter by date
        _filterByDate(context, DateTime.now());
        return;
      case 'week':
        // This would need custom implementation to filter by date range
        _filterByDateRange(context, DateTime.now().subtract(Duration(days: 7)), DateTime.now());
        return;
    }
    showResults(context);
  }

  void _filterByDate(BuildContext context, DateTime date) {
    // Custom implementation for date filtering
    // This could open a date picker or apply a predefined filter
    debugPrint('Filtering by date: $date');
  }

  void _filterByDateRange(BuildContext context, DateTime start, DateTime end) {
    // Custom implementation for date range filtering
    debugPrint('Filtering by date range: $start to $end');
  }
}

// Enhanced search functionality for chat sessions
class ChatSessionSearchDelegate extends SearchDelegate<ChatSessionSummary?> {
  @override
  ThemeData appBarTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: ResQLinkTheme.cardDark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white60),
        border: InputBorder.none,
      ),
      textTheme: TextTheme(
        titleLarge: TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }

  @override
  String get searchFieldLabel => 'Search chats...';

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: Icon(Icons.clear),
        onPressed: () {
          query = '';
          showSuggestions(context);
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return _buildEmptyState(context);
    }
    return _buildSearchResults(context);
  }

  Widget _buildSearchResults(BuildContext context) {
    return Container(
      color: ResQLinkTheme.backgroundDark,
      child: FutureBuilder<List<ChatSessionSummary>>(
        future: _searchChatSessions(query),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                color: ResQLinkTheme.primaryRed,
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error searching chats',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          final sessions = snapshot.data ?? [];

          if (sessions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, color: Colors.white30, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'No chats found',
                    style: TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              return _buildChatSearchResult(context, session);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      color: ResQLinkTheme.backgroundDark,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, color: Colors.white30, size: 64),
            SizedBox(height: 16),
            Text(
              'Search your chats',
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              'Type a device name or message to find chats',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatSearchResult(BuildContext context, ChatSessionSummary session) {
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      color: ResQLinkTheme.cardDark,
      child: InkWell(
        onTap: () => close(context, session),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: session.isOnline
                    ? ResQLinkTheme.safeGreen
                    : ResQLinkTheme.primaryRed.withOpacity(0.3),
                child: Text(
                  session.deviceName.isNotEmpty
                      ? session.deviceName[0].toUpperCase()
                      : 'D',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.deviceName,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (session.lastMessage != null) ...[
                      SizedBox(height: 4),
                      Text(
                        session.lastMessage!,
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    session.timeDisplay,
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  if (session.unreadCount > 0) ...[
                    SizedBox(height: 4),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: ResQLinkTheme.primaryRed,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        session.unreadCount.toString(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<ChatSessionSummary>> _searchChatSessions(String searchQuery) async {
    if (searchQuery.isEmpty) return [];

    try {
      final sessions = await DatabaseService.getChatSessions();

      return sessions.where((session) {
        final lowerQuery = searchQuery.toLowerCase();
        return session.deviceName.toLowerCase().contains(lowerQuery) ||
               session.deviceId.toLowerCase().contains(lowerQuery) ||
               (session.lastMessage?.toLowerCase().contains(lowerQuery) ?? false);
      }).toList();
    } catch (e) {
      debugPrint('❌ Error searching chat sessions: $e');
      return [];
    }
  }
}