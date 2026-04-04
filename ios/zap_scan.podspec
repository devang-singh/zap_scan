#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint zap_scan.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'zap_scan'
  s.version          = '1.1.0'
  s.summary          = 'High-precision card, barcode, and boarding pass scanner.'
  s.description      = <<-DESC
A high-precision scanning engine for Flutter that extracts complex data from credit cards, barcodes, and boarding passes using native OCR and EMV NFC.
                       DESC
  s.homepage         = 'https://github.com/devang-singh/zap_scan'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Devang Singh' => 'devangsingh665@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '16.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' 
  }
  s.swift_version = '5.0'

  # If your plugin requires privacy manifest, include it here
  s.resource_bundles = {
    'zap_scan_privacy' => ['Resources/PrivacyInfo.xcprivacy']
  }
end
