package com.scapia.zap_scan

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import android.content.Context
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.common.Barcode
import java.io.File

/** ZapScanPlugin */
class ZapScanPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "zap_scan")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        if (call.method == "getPlatformVersion") {
            result.success("Android ${android.os.Build.VERSION.RELEASE}")
        } else if (call.method == "recognizeText") {
            recognizeText(call, result)
        } else if (call.method == "recognizeBarcode") {
            recognizeBarcode(call, result)
        } else {
            result.notImplemented()
        }
    }

    private fun recognizeText(call: MethodCall, result: Result) {
        try {
            val imagePath = call.argument<String>("imagePath")
            val image: InputImage

            if (imagePath != null) {
                image = InputImage.fromFilePath(context, android.net.Uri.fromFile(File(imagePath)))
            } else {
                val bytes = call.argument<ByteArray>("bytes")
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")
                val rotation = call.argument<Int>("rotation")
                val format = call.argument<Int>("format")

                if (bytes == null || width == null || height == null || rotation == null || format == null) {
                    result.error("invalid_args", "Missing image or metadata arguments", null)
                    return
                }
                image = InputImage.fromByteArray(bytes, width, height, rotation, format)
            }

            val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

            recognizer.process(image)
                .addOnSuccessListener { visionText ->
                    result.success(visionText.text)
                }
                .addOnFailureListener { e ->
                    result.error("ocr_error", e.message, null)
                }
        } catch (e: Exception) {
            result.error("ocr_perform_error", e.message, null)
        }
    }

    private fun recognizeBarcode(call: MethodCall, result: Result) {
        try {
            val imagePath = call.argument<String>("imagePath")
            val image: InputImage

            if (imagePath != null) {
                image = InputImage.fromFilePath(context, android.net.Uri.fromFile(File(imagePath)))
            } else {
                val bytes = call.argument<ByteArray>("bytes")
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")
                val rotation = call.argument<Int>("rotation")
                val format = call.argument<Int>("format")

                if (bytes == null || width == null || height == null || rotation == null || format == null) {
                    result.error("invalid_args", "Missing image or metadata arguments", null)
                    return
                }
                image = InputImage.fromByteArray(bytes, width, height, rotation, format)
            }

            val options = BarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_ALL_FORMATS)
                .build()
            
            val scanner = BarcodeScanning.getClient(options)

            scanner.process(image)
                .addOnSuccessListener { barcodes ->
                    val payloadList = ArrayList<Map<String, String>>()
                    for (barcode in barcodes) {
                        val rawValue = barcode.rawValue
                        val formatStr = barcode.format.toString()
                        if (rawValue != null) {
                            val map = HashMap<String, String>()
                            map["rawValue"] = rawValue
                            map["format"] = formatStr
                            payloadList.add(map)
                        }
                    }
                    result.success(payloadList)
                }
                .addOnFailureListener { e ->
                    result.error("barcode_error", e.message, null)
                }
        } catch (e: Exception) {
            result.error("barcode_perform_error", e.message, null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
