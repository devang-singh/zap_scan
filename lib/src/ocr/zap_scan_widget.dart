import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'universal_scanner_controller.dart';

/// A widget that provides a live camera preview for scanning cards and barcodes.
/// 
/// It automatically handles the camera initialization, the preview aspect ratio,
/// and stops the camera when the widget is disposed.
class ZapScanWidget extends StatefulWidget {
  /// The controller that manages the scanning session and consensus logic.
  final UniversalScannerController controller;
  
  /// A widget to display while the camera is initializing.
  final Widget? loader;
  
  /// A color to use as the background for the loader.
  final Color? backgroundColor;

  /// Default constructor for [ZapScanWidget].
  const ZapScanWidget({
    super.key,
    required this.controller,
    this.loader,
    this.backgroundColor,
  });

  @override
  State<ZapScanWidget> createState() => _ZapScanWidgetState();
}

class _ZapScanWidgetState extends State<ZapScanWidget> {
  @override
  void initState() {
    super.initState();
    widget.controller.startCamera();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller.cameraController;
        
        if (controller == null || !controller.value.isInitialized) {
          return Container(
            color: widget.backgroundColor ?? Colors.black,
            child: Center(child: widget.loader ?? const CircularProgressIndicator()),
          );
        }

        return Container(
          color: widget.backgroundColor ?? Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: 1 / controller.value.aspectRatio,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}
