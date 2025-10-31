class SoilHealthService {
  double calculateHealthScore(List<double> recentTemps) {
    if (recentTemps.isEmpty) return 0;

    double avgTemp = recentTemps.reduce((a, b) => a + b) / recentTemps.length;

    // Score calculation based on ideal range (18-25°C)
    double score = 0;
    if (avgTemp < 10 || avgTemp > 35) {
      score = 20; // Extreme low/high
    } else if (avgTemp >= 10 && avgTemp < 18) {
      // Below ideal, score decreases as it gets colder
      score = 60 - (18 - avgTemp) * 2;
    } else if (avgTemp >= 18 && avgTemp <= 25) {
      // Near ideal, high score
      score = 90 + (avgTemp - 18) * 1.1;
    } else if (avgTemp > 25 && avgTemp <= 35) {
      // Above ideal, score decreases as it gets hotter
      score = 90 - (avgTemp - 25) * 2;
    }

    return score.clamp(0, 100);
  }
}