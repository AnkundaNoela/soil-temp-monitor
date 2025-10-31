// lib/models/temperature_reading.dart

class TemperatureReading {
  final DateTime timestamp;
  final double temperature;

  TemperatureReading({required this.timestamp, required this.temperature});

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'temperature': temperature,
  };

  factory TemperatureReading.fromJson(Map<String, dynamic> json) =>
      TemperatureReading(
        timestamp: DateTime.parse(json['timestamp']),
        temperature: json['temperature'].toDouble(),
      );
}
