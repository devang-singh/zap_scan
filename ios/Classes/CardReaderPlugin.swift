import Flutter
import UIKit
import Vision

public class CardReaderPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "card_reader_plugin", binaryMessenger: registrar.messenger())
    let instance = CardReaderPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "getPlatformVersion" {
      result("iOS " + UIDevice.current.systemVersion)
    } else if call.method == "recognizeText" {
      recognizeText(call: call, result: result)
    } else if call.method == "recognizeBarcode" {
      recognizeBarcode(call: call, result: result)
    } else {
      result(FlutterMethodNotImplemented)
    }
  }

  private func recognizeText(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_args", message: "Missing arguments", details: nil))
        return
    }

    let requestHandler: VNImageRequestHandler

    if let imagePath = args["imagePath"] as? String {
        guard let uiImage = UIImage(contentsOfFile: imagePath),
              let cgImage = uiImage.cgImage else {
            result(FlutterError(code: "image_error", message: "Could not load image from path", details: nil))
            return
        }
        requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    } else {
        guard let flutterData = args["bytes"] as? FlutterStandardTypedData,
              let width = args["width"] as? Int,
              let height = args["height"] as? Int else {
            result(FlutterError(code: "invalid_args", message: "Missing image bytes or dimensions", details: nil))
            return
        }

        let bytes = flutterData.data
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4 

        guard let provider = CGDataProvider(data: bytes as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            result(FlutterError(code: "image_error", message: "Could not create image from bytes", details: nil))
            return
        }
        requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    }

    let request = VNRecognizeTextRequest { (request, error) in
        if let error = error {
            result(FlutterError(code: "ocr_error", message: error.localizedDescription, details: nil))
            return
        }

        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            result("")
            return
        }

        var extractedText = ""
        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            extractedText += topCandidate.string + "\n"
        }

        result(extractedText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    request.recognitionLevel = .accurate

    do {
        try requestHandler.perform([request])
    } catch {
        result(FlutterError(code: "ocr_perform_error", message: error.localizedDescription, details: nil))
    }
  }

  private func recognizeBarcode(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_args", message: "Missing arguments", details: nil))
        return
    }

    let requestHandler: VNImageRequestHandler

    if let imagePath = args["imagePath"] as? String {
        guard let uiImage = UIImage(contentsOfFile: imagePath),
              let cgImage = uiImage.cgImage else {
            result(FlutterError(code: "image_error", message: "Could not load image from path", details: nil))
            return
        }
        requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    } else {
        guard let flutterData = args["bytes"] as? FlutterStandardTypedData,
              let width = args["width"] as? Int,
              let height = args["height"] as? Int else {
            result(FlutterError(code: "invalid_args", message: "Missing image bytes or dimensions", details: nil))
            return
        }

        let bytes = flutterData.data
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4 

        guard let provider = CGDataProvider(data: bytes as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            result(FlutterError(code: "image_error", message: "Could not create image from bytes", details: nil))
            return
        }
        requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    }

    let request = VNDetectBarcodesRequest { (request, error) in
        if let error = error {
            result(FlutterError(code: "barcode_error", message: error.localizedDescription, details: nil))
            return
        }

        guard let observations = request.results as? [VNBarcodeObservation] else {
            result([])
            return
        }

        var payloadList: [[String: String]] = []
        for observation in observations {
            if let rawValue = observation.payloadStringValue {
                var formatStr = "UNKNOWN"
                if #available(iOS 14.0, *) {
                    formatStr = observation.symbology.rawValue
                }
                payloadList.append(["rawValue": rawValue, "format": formatStr])
            }
        }

        result(payloadList)
    }

    do {
        try requestHandler.perform([request])
    } catch {
        result(FlutterError(code: "barcode_perform_error", message: error.localizedDescription, details: nil))
    }
  }
}
