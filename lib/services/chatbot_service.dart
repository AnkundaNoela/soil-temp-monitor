// lib/services/chatbot_service.dart
// FINAL VERSION WITH STABLE MODEL NAME ('gemini-1.0-pro')

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/temperature_reading.dart';
import 'weather_service.dart';
import '../config/api_keys.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

// --- Your Existing Models ---
class ChatMessage {
  final String message;
  final bool isUser;
  final DateTime timestamp;
  ChatMessage(
      {required this.message, required this.isUser, required this.timestamp});
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  @override
  String toString() => message;
}

extension IterableExtension<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}

class ChatbotService {
  static final ChatbotService _instance = ChatbotService._internal();
  factory ChatbotService() => _instance;

  ChatbotService._internal() {
    _initializeGemini();
  }

  final List<ChatMessage> _conversationHistory = [];
  GenerativeModel? _geminiModel;
  ChatSession? _chatSession;
  bool _isGeminiEnabled = false;

  List<ChatMessage> get conversationHistory => _conversationHistory;
  bool get isAIEnabled => _isGeminiEnabled;

  void _initializeGemini() {
    try {
      if (!ApiKeys.isConfigured) {
        print('_initializeGemini CHECK FAILED: API key is not configured.');
        _isGeminiEnabled = false;
        return;
      }

      print("Attempting to initialize Gemini with a valid API key...");

      final googleSearchTool = Tool(
        functionDeclarations: [
          FunctionDeclaration(
            'google_search',
            'Performs a Google search for external information.',
            Schema(
              SchemaType.object,
              properties: {
                'query':
                    Schema(SchemaType.string, description: 'The search query'),
              },
              requiredProperties: ['query'],
            ),
          ),
        ],
      );

      _geminiModel = GenerativeModel(
        // ===================================================================
        //            THE FINAL, MOST STABLE MODEL NAME
        // ===================================================================
        model: 'models/gemini-2.5-pro',
        apiKey: ApiKeys.geminiApiKey,
        tools: [googleSearchTool],
        generationConfig: GenerationConfig(temperature: 0.7),
      );

      final initialPrompt = Content.text(
          "You are AgriBot, an expert agricultural AI assistant for farmers in Uganda. Your entire purpose is to provide advice that is DIRECTLY and EXPLICITLY based on the real-time data provided. "
          "\n--- YOUR CORE INSTRUCTIONS ---"
          "\n1.  **DATA IS EVERYTHING:** You will be given a block of `[CONTEXT DATA]`. You MUST base your entire response on this data. Start your response by acknowledging the data you are using. For example: 'Given that your soil temperature is X°C...' or 'Since the weather forecast is Y...'. "
          "\n2.  **THINK STEP-BY-STEP:** Before you answer, you will follow a silent, step-by-step reasoning process. First, analyze each piece of context data. Second, connect the data to the farmer's question. Third, formulate a specific, actionable recommendation. "
          "\n3.  **NO GENERIC ANSWERS:** You are forbidden from giving generic advice. "
          "    - WRONG: 'You can plant maize in the rainy season.' "
          "    - RIGHT: 'Since it's currently the first rainy season and your soil temperature is a stable 26°C, now is an excellent time to plant maize.' "
          "\n4.  **USE TOOLS FOR EXTERNAL KNOWLEDGE:** If the user asks for something not in the context data (like market prices, news, definitions), and only then, use the `google_search` function. "
          "\n5.  **BE A UGANDAN FARMER'S COMPANION:** Be helpful, encouraging, and use simple language. Keep responses focused and concise.");

      _chatSession = _geminiModel!.startChat(history: [
        initialPrompt,
        Content.model([
          TextPart(
              "Understood. I will strictly follow all rules. My primary function is to provide specific advice by first analyzing the provided context data and thinking step-by-step.")
        ])
      ]);

      _isGeminiEnabled = true;
      print('✅ Gemini AI with SUPERIOR instructions initialized successfully');
    } catch (e) {
      print('❌ Gemini initialization failed inside the CATCH block.');
      print('❌ THE SPECIFIC ERROR IS: $e');
      _isGeminiEnabled = false;
    }
  }

  Future<String> getResponse({
    required String userMessage,
    required double currentTemp,
    required List<TemperatureReading> readings,
    double? ambientTemp,
    List<ForecastDay>? forecast,
  }) async {
    _conversationHistory.add(ChatMessage(
        message: userMessage, isUser: true, timestamp: DateTime.now()));
    String response = await _generateResponse(
        userMessage: userMessage,
        currentTemp: currentTemp,
        readings: readings,
        ambientTemp: ambientTemp,
        forecast: forecast);
    _conversationHistory.add(ChatMessage(
        message: response, isUser: false, timestamp: DateTime.now()));
    return response;
  }

  Future<String> _generateResponse({
    required String userMessage,
    required double currentTemp,
    required List<TemperatureReading> readings,
    double? ambientTemp,
    List<ForecastDay>? forecast,
  }) async {
    if (_isGeminiEnabled) {
      return await _getAIResponseWithTools(
          userMessage: userMessage,
          currentTemp: currentTemp,
          readings: readings,
          ambientTemp: ambientTemp,
          forecast: forecast);
    } else {
      return "My AI brain is currently offline. Please check the connection and API keys.";
    }
  }

  Future<String> _getAIResponseWithTools({
    required String userMessage,
    required double currentTemp,
    required List<TemperatureReading> readings,
    double? ambientTemp,
    List<ForecastDay>? forecast,
  }) async {
    if (_chatSession == null) return "⚠️ AI assistant is not available.";

    try {
      String contextMessage = _buildAIContext(
          userMessage: userMessage,
          currentTemp: currentTemp,
          readings: readings,
          ambientTemp: ambientTemp,
          forecast: forecast);

      print("\n\n[CONTEXT SENT TO AI]\n$contextMessage\n\n");

      var response =
          await _chatSession!.sendMessage(Content.text(contextMessage));

      while (response.functionCalls.isNotEmpty) {
        final functionCall = response.functionCalls.first;
        final query = functionCall.args['query'] as String;
        final searchResult = await _executeGoogleSearch(query);
        response = await _chatSession!.sendMessage(
            Content.functionResponse(functionCall.name, searchResult));
      }

      return response.text?.trim() ??
          'I had trouble understanding that. Could you rephrase?';
    } catch (e) {
      print('❌ AI Error: $e');
      return "Sorry, I encountered an error. Please try again.";
    }
  }

  String _buildAIContext({
    required String userMessage,
    required double currentTemp,
    required List<TemperatureReading> readings,
    double? ambientTemp,
    List<ForecastDay>? forecast,
  }) {
    StringBuffer context = StringBuffer();
    context.writeln(
        "Here is the data and the user's question. Follow your core instructions to provide a specific, data-driven answer.");
    context.writeln("\n[CONTEXT DATA]");
    context.writeln(
        "- Current Soil Temperature: ${currentTemp > 0 ? '${currentTemp.toStringAsFixed(1)}°C' : 'Not Available'}");
    if (ambientTemp != null && ambientTemp > 0) {
      context.writeln(
          "- Current Air Temperature: ${ambientTemp.toStringAsFixed(1)}°C");
    }
    if (forecast != null && forecast.isNotEmpty) {
      final today = forecast.first;
      context.writeln(
          "- Weather Forecast: ${today.condition}, high of ${today.maxTempC.toStringAsFixed(0)}°C.");
    }
    final month = DateTime.now().month;
    String season = (month >= 3 && month <= 5)
        ? 'first rainy season'
        : (month >= 9 && month <= 11)
            ? 'second rainy season'
            : 'dry season';
    context.writeln("- Current Season: $season in Uganda.");
    context.writeln("\n[FARMER'S QUESTION]");
    context.writeln(userMessage);
    return context.toString();
  }

  Future<Map<String, dynamic>> _executeGoogleSearch(String query) async {
    try {
      final apiKey = ApiKeys.googleSearchApiKey;
      final cx = ApiKeys.googleSearchEngineId;
      if (apiKey.contains('YOUR_') || cx.contains('YOUR_')) {
        return {'error': 'Google Search is not configured.'};
      }
      final uri = Uri.https('www.googleapis.com', '/customsearch/v1',
          {'key': apiKey, 'cx': cx, 'q': query, 'num': '2'});
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List?;
        if (items != null && items.isNotEmpty) {
          final summaries = items
              .map((item) =>
                  'Source Title: ${item['title']}\nInformation: ${item['snippet']}')
              .toList();
          return {'results': summaries.join('\n\n')};
        }
        return {'results': 'No relevant information was found.'};
      }
      return {'error': 'Failed to fetch search results.'};
    } catch (e) {
      return {'error': 'An exception occurred during search.'};
    }
  }

  void clearHistory() {
    _conversationHistory.clear();
    _initializeGemini();
  }
}
