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
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 1 / controller.value.aspectRatio,
                  child: CameraPreview(controller),
                ),
                if (widget.controller.showDebugOverlay)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        border: const Border(top: BorderSide(color: Colors.green, width: 1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "RAW OCR STREAM",
                                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              Row(
                                children: [
                                  if (widget.controller.isDebugStreamPaused)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 8.0),
                                      child: Text(
                                        "PAUSED",
                                        style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 10),
                                      ),
                                    ),
                                  Material(
                                    color: Colors.transparent,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: Icon(
                                        widget.controller.isDebugStreamPaused ? Icons.play_arrow : Icons.pause,
                                        color: widget.controller.isDebugStreamPaused ? Colors.orange : Colors.green,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        widget.controller.isDebugStreamPaused = !widget.controller.isDebugStreamPaused;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(color: Colors.green, height: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Text(
                                widget.controller.rawLines.join("\n"),
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
