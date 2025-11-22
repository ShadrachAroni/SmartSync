import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../services/weather_service.dart';

/// Weather icon widget using Lottie animations
class LottieWeatherIcon extends StatelessWidget {
  final WeatherCondition condition;
  final double size;

  const LottieWeatherIcon({
    super.key,
    required this.condition,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    String animationPath;
    
    switch (condition) {
      case WeatherCondition.sunny:
        animationPath = 'assets/animations/sun.json';
        break;
      case WeatherCondition.cloudy:
      case WeatherCondition.partlyCloudy:
        animationPath = 'assets/animations/cloud.json';
        break;
      case WeatherCondition.rainy:
        animationPath = 'assets/animations/rain-cloud.json';
        break;
      case WeatherCondition.stormy:
        animationPath = 'assets/animations/cloud-with-lightning.json';
        break;
      case WeatherCondition.snowy:
      case WeatherCondition.foggy:
        animationPath = 'assets/animations/cloud.json';
        break;
    }

    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        animationPath,
        fit: BoxFit.contain,
        repeat: true,
      ),
    );
  }
}

