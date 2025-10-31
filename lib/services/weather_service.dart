import 'dart:convert';
import 'package:http/http.dart' as http;

// NEW Model for hourly forecast
class ForecastHour {
  final DateTime time;
  final double tempC;
  final String iconUrl;
  final double chanceOfRain;

  ForecastHour({
    required this.time,
    required this.tempC,
    required this.iconUrl,
    required this.chanceOfRain,
  });
}

// Model for a single forecast day (updated to hold hourly data)
class ForecastDay {
  final DateTime date;
  final double maxTempC;
  final double minTempC;
  final String condition;
  final String iconUrl;
  final List<ForecastHour> hourlyForecast; // <--- ADDED

  ForecastDay({
    required this.date,
    required this.maxTempC,
    required this.minTempC,
    required this.condition,
    required this.iconUrl,
    required this.hourlyForecast, // <--- ADDED
  });
}

class WeatherService {
  final String apiKey = "8052c37272104e0f860145336252810"; // Your WeatherAPI.com key

  // ... (getAmbientTemperature remains the same) ...
  Future<double?> getAmbientTemperature(double lat, double lon) async {
    if (apiKey.isEmpty) {
      return null;
    }
    
    final url =
        'https://api.weatherapi.com/v1/current.json?key=$apiKey&q=$lat,$lon';
        
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body);
        return data['current']['temp_c']?.toDouble();
      } catch (e) {
        print("Error parsing current weather data: $e");
        return null;
      }
    } else {
      print("Failed to load current weather data: ${response.statusCode}");
      return null;
    }
  }


  // MODIFIED FUNCTION: Fetch 3-day forecast with hourly data
  Future<List<ForecastDay>> getForecast(double lat, double lon) async {
    if (apiKey.isEmpty) {
      return [];
    }

    final url =
        'https://api.weatherapi.com/v1/forecast.json?key=$apiKey&q=$lat,$lon&days=3';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body);
        final forecastDaysJson = data['forecast']['forecastday'] as List;
        
        return forecastDaysJson.map((dayData) {
          // Parse Hourly Data
          final hourlyJson = dayData['hour'] as List;
          final hourlyForecast = hourlyJson.map((hourData) {
            return ForecastHour(
              time: DateTime.parse(hourData['time']),
              tempC: hourData['temp_c'].toDouble(),
              iconUrl: 'https:' + (hourData['condition']['icon'] as String),
              chanceOfRain: hourData['chance_of_rain'].toDouble(),
            );
          }).toList();

          return ForecastDay(
            date: DateTime.parse(dayData['date']),
            maxTempC: dayData['day']['maxtemp_c'].toDouble(),
            minTempC: dayData['day']['mintemp_c'].toDouble(),
            condition: dayData['day']['condition']['text'],
            iconUrl: 'https:${dayData['day']['condition']['icon'] as String}',
            hourlyForecast: hourlyForecast, // <--- SAVED HOURLY DATA
          );
        }).toList();

      } catch (e) {
        print("Error parsing forecast data: $e");
        return [];
      }
    } else {
      print("Failed to load forecast data: ${response.statusCode}");
      return [];
    }
  }
}