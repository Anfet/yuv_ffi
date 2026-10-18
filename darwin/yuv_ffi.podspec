#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint yuv_ffi.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'yuv_ffi'
  s.version          = '0.5.2'
  s.summary          = 'High-performance YUV/BGRA image processing for Flutter via native C/FFI.'
  s.description      = <<-DESC
yuv_ffi is a Flutter/Dart package for high-performance image processing on YUV/BGRA frames using native C + FFI. It provides format conversions, crop/rotate/flip, effects, blur, and plane-based APIs with row/pixel stride support.
                       DESC
  s.homepage         = 'https://github.com/Anfet/yuv_ffi'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Anfet' => 'oleg.toplionkin@gmail.com' }

  # A podspec cannot reference paths outside the pod directory, so
  # yuv_ffi/Sources/yuv_ffi holds one forwarder .c file per source in
  # src/CMakeLists.txt. Each forwarder relatively includes its `../src/*`
  # counterpart, so the C sources are shared among all target platforms and
  # the same directory doubles as the Swift Package Manager target.
  s.source           = { :path => '.' }
  s.source_files     = 'yuv_ffi/Sources/yuv_ffi/*.c'

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'

  # Flutter.framework does not contain a i386 slice.
  s.ios.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.osx.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  # Dart process lookups do not create linker references. Keep the ABI entry
  # points in the consumer image when CocoaPods builds a static archive.
  abi_symbols = %w[
    yuv_convert_v1 yuv_black_white_v1 yuv_grayscale_v1 yuv_negate_v1
    yuv_gaussian_blur_v1 yuv_mean_blur_v1 yuv_box_blur_v1 yuv_crop_v1
    yuv_flip_v1 yuv_rotate_v1 yuv_chroma_swap_v1
  ]
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) ' + abi_symbols.map { |symbol| "-Wl,-u,_#{symbol}" }.join(' ')
  }
  s.swift_version = '5.0'
end
