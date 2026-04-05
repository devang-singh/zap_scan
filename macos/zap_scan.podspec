#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint zap_scan.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'zap_scan'
  s.version          = '1.1.1'
  s.summary          = 'High-precision card, barcode, and boarding pass scanner.'
  s.description      = <<-DESC
A high-precision scanning engine for Flutter that extracts complex data from credit cards, barcodes, and boarding passes using native OCR and EMV NFC.
                       DESC
  s.homepage         = 'https://github.com/devang-singh/zap_scan'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Devang Singh' => 'devangsingh665@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  # Resource bundle for Privacy Manifest
  s.resource_bundles = {
    'zap_scan_privacy' => ['Resources/PrivacyInfo.xcprivacy']
  }
end
