import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'universal_scanner_controller.dart';

class ZapScanWidget extends StatefulWidget {
  final UniversalScannerController controller;
  final Widget loader;

  final double? width;
  final double? height;

  const ZapScanWidget({
    super.key,
    required this.controller,
    this.loader = const SizedBox.shrink(),
    this.width,
    this.height,
  });

  @override
  State<ZapScanWidget> createState() => _ZapScanWidgetState();
}

class _ZapScanWidgetState extends State<ZapScanWidget> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.startCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      if (!widget.controller.isPaused) widget.controller.stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (!widget.controller.isPaused) widget.controller.startCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.stopCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final cameraReady = widget.controller.cameraController?.value.isInitialized ?? false;

          if (!cameraReady) return Center(child: widget.loader);

          final cameraController = widget.controller.cameraController!;
          final previewSize = cameraController.value.previewSize;
          if (previewSize == null) return Center(child: widget.loader);

          return ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: previewSize.height,
                height: previewSize.width,
                child: CameraPreview(cameraController),
              ),
            ),
          );
        },
      ),
    );
  }
}
