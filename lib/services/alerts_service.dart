class AlertsService {
  String? checkTemperatureAlerts(double soilTemp, double ambientTemp) {
    if (soilTemp <= 2) return "⚠ Frost Alert: Soil temperature is very low! Protect sensitive plants.";
    if (soilTemp >= 35) return "⚠ High Temp Alert: Soil temperature is very high! Increase shade/moisture.";
    if (ambientTemp <= 0 && soilTemp < 5) return "⚠ Frost Risk: Ambient temperature is freezing! Prepare for soil frost.";
    return null;
  }

  String predictTrend(double tempTrend) {
    // trendPerDay is in °C/day
    if (tempTrend > 1.5) return "Soil is warming up quickly - good for warm-season crops.";
    if (tempTrend > 0.5) return "Soil is warming up gradually.";
    if (tempTrend < -1.5) return "Soil is cooling down quickly - watch frost-sensitive plants.";
    if (tempTrend < -0.5) return "Soil is cooling down gradually.";
    return "Soil temperature stable.";
  }
}