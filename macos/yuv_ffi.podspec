#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint yuv_ffi.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'yuv_ffi'
  s.version          = '0.4.0'
  s.summary          = 'High-performance YUV/BGRA image processing for Flutter via native C/FFI.'
  s.description      = <<-DESC
yuv_ffi is a Flutter/Dart package for high-performance image processing on YUV/BGRA frames using native C + FFI. It provides format conversions, crop/rotate/flip, effects, blur, and plane-based APIs with row/pixel stride support.
                       DESC
  s.homepage         = 'https://github.com/Anfet/yuv_ffi'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Anfet' => 'oleg.toplionkin@gmail.com' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
