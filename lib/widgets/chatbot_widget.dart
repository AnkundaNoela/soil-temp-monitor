// lib/widgets/chatbot_widget.dart

import 'package:flutter/material.dart';
import 'dart:async';
import '../services/chatbot_service.dart';
import '../services/bluetooth_manager.dart';
import '../services/weather_service.dart';

class ChatbotFAB extends StatelessWidget {
  const ChatbotFAB({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => const ChatbotBottomSheet(),
        );
      },
      backgroundColor: Colors.green.shade600,
      child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
    );
  }
}

class ChatbotBottomSheet extends StatefulWidget {
  const ChatbotBottomSheet({super.key});

  @override
  State<ChatbotBottomSheet> createState() => _ChatbotBottomSheetState();
}

class _ChatbotBottomSheetState extends State<ChatbotBottomSheet> {
  final ChatbotService _chatbot = ChatbotService();
  final BluetoothManager _bleManager = BluetoothManager();
  final WeatherService _weatherService = WeatherService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  List<ForecastDay> _forecast = [];

  @override
  void initState() {
    super.initState();
    _loadWeatherData();

    // Send welcome message if chat history is empty
    if (_chatbot.conversationHistory.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendWelcomeMessage();
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadWeatherData() async {
    try {
      const double lat = 0.31361;
      const double lon = 32.58111;
      final forecast = await _weatherService.getForecast(lat, lon);
      setState(() {
        _forecast = forecast;
      });
    } catch (e) {
      // Silently fail - chatbot will work without weather data
      print("Could not load weather data: $e");
    }
  }

  void _sendWelcomeMessage() {
    setState(() {
      _chatbot.conversationHistory.add(
        ChatMessage(
          message:
              "👋 Hello! I'm your agricultural assistant.\n\n"
              "I can help you with:\n"
              "🌡️ Soil temperature analysis\n"
              "🌦️ Weather forecasts\n"
              "🌱 Planting recommendations\n"
              "💧 Irrigation advice\n"
              "🗺️ App navigation\n\n"
              "What would you like to know?",
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final message = _messageController.text.trim();
    _messageController.clear();

    // The user's message will be added inside getResponse.
    // We set state here to show the loading indicator immediately.
    setState(() {
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      // getResponse handles adding BOTH the user message and the bot response to history.
      await _chatbot.getResponse(
        userMessage: message,
        currentTemp: _bleManager.currentTemp,
        readings: _bleManager.readings,
        ambientTemp: _forecast.isNotEmpty ? _forecast.first.maxTempC : null,
        forecast: _forecast,
      );

      // We just need to update the state to show the new messages from the history.
      // We no longer manually add the bot response here, as it's already in the history.
      setState(() {
        _isLoading = false;
      });

      _scrollToBottom();
    } catch (e) {
      // If an error occurs, we now add an error message to the history for the user to see.
      _chatbot.conversationHistory.add(
        ChatMessage(
          message: "Sorry, I encountered an error. Please try again.",
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: screenHeight * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade600,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.agriculture,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AgriBot Assistant',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Your farming companion',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Quick suggestions
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildQuickSuggestion('Current temp', Icons.thermostat),
                  const SizedBox(width: 8),
                  _buildQuickSuggestion('Weather', Icons.wb_sunny),
                  const SizedBox(width: 8),
                  _buildQuickSuggestion('What to plant', Icons.eco),
                  const SizedBox(width: 8),
                  _buildQuickSuggestion('Irrigation', Icons.water_drop),
                  const SizedBox(width: 8),
                  _buildQuickSuggestion('Navigate', Icons.map),
                ],
              ),
            ),
          ),

          // Chat messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _chatbot.conversationHistory.length,
              itemBuilder: (context, index) {
                final message = _chatbot.conversationHistory[index];
                return _buildMessageBubble(message);
              },
            ),
          ),

          // Loading indicator
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.green.shade600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Thinking...'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Input field
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: keyboardHeight > 0 ? keyboardHeight + 12 : 12,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Ask me anything...',
                        border: InputBorder.none,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickSuggestion(String text, IconData icon) {
    return InkWell(
      onTap: () {
        _messageController.text = text;
        _sendMessage();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.green.shade700),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: message.isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.agriculture,
                size: 20,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: message.isUser
                    ? Colors.green.shade600
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(message.isUser ? 16 : 4),
                  bottomRight: Radius.circular(message.isUser ? 4 : 16),
                ),
              ),
              child: Text(
                message.message,
                style: TextStyle(
                  color: message.isUser ? Colors.white : Colors.black87,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, size: 20, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}
