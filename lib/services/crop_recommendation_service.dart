import 'package:flutter/material.dart'
    show RangeValues; // Added for RangeValues

class CropRecommendationService {
  // RangeValues is typically a part of the Flutter framework (material.dart)
  final Map<String, RangeValues> cropTempRanges = {
    "Tomatoes": RangeValues(18, 30),
    "Carrots": RangeValues(16, 24),
    "Lettuce": RangeValues(10, 20),
    "Potatoes": RangeValues(15, 25),
  };

  List<String> recommendCrops(double soilTemp) {
    List<String> recommended = [];
    cropTempRanges.forEach((crop, range) {
      if (soilTemp >= range.start && soilTemp <= range.end) {
        recommended.add(crop);
      }
    });
    return recommended;
  }

  // Assumes trendPerDay is in °C/day
  String estimatePlantingWindow(double soilTemp, double trendPerDay) {
    int daysToIdeal = 0;

    // Find the nearest ideal start temp (for planting)
    double targetTemp = double.infinity;
    for (var range in cropTempRanges.values) {
      if (soilTemp < range.start && range.start < targetTemp) {
        targetTemp = range.start.toDouble();
      }
    }

    if (targetTemp == double.infinity) {
      return "Soil temp is currently ideal for some crops.";
    }

    if (trendPerDay > 0.1) {
      // Soil is warming up, calculate days to reach target temp
      daysToIdeal = ((targetTemp - soilTemp) / trendPerDay).ceil();
      if (daysToIdeal < 0) return "Soil is currently ideal for some crops.";
      return "Optimal planting window in $daysToIdeal days (warming trend).";
    } else if (trendPerDay < -0.1) {
      // Soil is cooling, suggest planting now if temp is still acceptable
      return "Soil is cooling. Consider planting now or wait for the next season.";
    } else {
      return "Soil temperature is stable. Planting window may be distant.";
    }
  }
}
