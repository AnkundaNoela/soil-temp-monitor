import 'package:flutter/material.dart';
import '../services/crop_recommendation_service.dart';

class InsightsDashboard extends StatelessWidget {
  final double soilTemp;
  final double tempTrend;

  const InsightsDashboard({super.key, required this.soilTemp, required this.tempTrend});

  @override
  Widget build(BuildContext context) {
    final cropService = CropRecommendationService();
    final recommendedCrops = cropService.recommendCrops(soilTemp);
    final plantingWindow = cropService.estimatePlantingWindow(soilTemp, tempTrend);

    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Crop Insights"),
        backgroundColor: Colors.green.shade700,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInsightCard(
              icon: Icons.thermostat_outlined,
              title: "Current Soil Temperature",
              value: "${soilTemp.toStringAsFixed(1)}°C",
              color: Colors.orange,
            ),
            const SizedBox(height: 16),
            _buildInsightCard(
              icon: tempTrend > 0.1 ? Icons.trending_up : tempTrend < -0.1 ? Icons.trending_down : Icons.trending_flat,
              title: "Temp Trend (Per Day)",
              value: "${tempTrend.toStringAsFixed(2)}°C/day",
              color: tempTrend > 0.1 ? Colors.red : tempTrend < -0.1 ? Colors.blue : Colors.grey,
            ),
            const SizedBox(height: 24),
            Text("Crop Recommendations:", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
            const SizedBox(height: 8),
            Expanded(
              child: recommendedCrops.isEmpty
                  ? Center(child: Text("No crops match the current soil temperature range.", style: TextStyle(color: Colors.black54)))
                  : ListView(
                      children: recommendedCrops.map((crop) => ListTile(
                            leading: const Icon(Icons.eco, color: Colors.green),
                            title: Text(crop, style: const TextStyle(fontWeight: FontWeight.w500)),
                            subtitle: const Text("Ideal temperature for planting."),
                          )).toList(),
                    ),
            ),
            const SizedBox(height: 16),
            _buildPlantingWindowCard(plantingWindow),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightCard({required IconData icon, required String title, required String value, required Color color}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, size: 30, color: color),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, color: Colors.black54)),
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlantingWindowCard(String plantingWindow) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.lightGreen.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.lightGreen.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.access_time, color: Colors.green.shade700, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Planting Window Forecast", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(plantingWindow, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}