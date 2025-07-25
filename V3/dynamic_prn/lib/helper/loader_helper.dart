import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class LoaderHelper {
  static Widget _buildLoaderBox({
    required Widget child,
    required double width,
    required double height,
  }) {
    return Center(
      child: Container(
        width: width + 40,
        height: height + 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              spreadRadius: 2,
              offset: const Offset(4, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(10),
        child: child,
      ),
    );
  }

  static Widget scaleLoader({double width = 200, double height = 200}) {
    return _buildLoaderBox(
      width: width,
      height: height,
      child: Lottie.asset(
        'assets/animation/loading_scale.json',
        width: width,
        height: height,
        fit: BoxFit.contain,
      ),
    );
  }

  static Widget printerLoader({double width = 200, double height = 200}) {
    return _buildLoaderBox(
      width: width,
      height: height,
      child: Lottie.asset(
        'assets/animation/loading_printer.json',
        width: width,
        height: height,
        fit: BoxFit.contain,
      ),
    );
  }

  static Widget bluetoothLoader({double width = 100, double height = 100}) {
    return _buildLoaderBox(
      width: width,
      height: height,
      child: Lottie.asset(
        'assets/animation/loading_bluetooth.json',
        width: width,
        height: height,
        fit: BoxFit.contain,
      ),
    );
  }

  static Widget defaultLoader({double width = 100, double height = 100}) {
    return _buildLoaderBox(
      width: width,
      height: height,
      child: const CircularProgressIndicator(),
    );
  }
}
