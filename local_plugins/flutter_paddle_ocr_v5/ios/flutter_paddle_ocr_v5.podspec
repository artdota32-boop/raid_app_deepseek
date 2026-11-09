Pod::Spec.new do |s|
  s.name             = 'flutter_paddle_ocr_v5'
  s.version          = '0.0.1'
  s.summary          = 'On-device OCR for Flutter, powered by PaddleOCR-compatible PP-OCR models and ONNX Runtime.'
  s.description      = <<-DESC
On-device OCR for Flutter. Wraps a PaddleOCR-style mobile OCR pipeline
(detection -> optional angle classification -> recognition) behind a
Flutter MethodChannel handler.
                       DESC
  s.homepage         = 'https://github.com/mencomao/flutter-paddle-ocr'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Mencomao' => 'opensource@mencomao.com' }
  s.source           = { :path => '.' }

  s.source_files     = 'Classes/**/*.{h,hpp,m,mm,cpp}', 'Classes/**/*.swift'
  s.public_header_files = 'Classes/PaddleOcrEngine.h'
  s.preserve_paths   = 'Frameworks/**/*'

  s.dependency       'Flutter'
  # 1.20.x is the newest onnxruntime-c line that still supports iOS 13.
  s.dependency       'onnxruntime-c', '~> 1.20.0'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'

  # Fetch OpenCV once per `pod install`; ONNX Runtime is provided by CocoaPods.
  s.prepare_command = <<-CMD
    set -e
    mkdir -p Frameworks
    cd Frameworks
    if [ ! -d opencv2.framework ]; then
      # OpenCV 4.5.5 — needed for `imgcodecs.hpp` (upstream ppocr includes it;
      # the older 2.4 framework at paddlelite-demo/.../opencv2.framework.tar.gz
      # still lived in highgui and breaks the build).
      curl -sSL -o cv.tar.gz "https://paddlelite-demo.bj.bcebos.com/libs/ios/opencv-4.5.5-ios-framework.tar.gz"
      tar xzf cv.tar.gz
      rm cv.tar.gz
    fi
    # Upstream ppocr_demo uses `#include "opencv2/core.hpp"` (quote form). Clang
    # only resolves that path via header-path search, not framework-aware
    # lookup, so point HEADER_SEARCH_PATHS at Frameworks/ and symlink the
    # framework Headers dir as `opencv2`.
    ln -sfn opencv2.framework/Headers opencv2
  CMD

  # OpenCV is a fat framework with arm64 device + x86_64 sim slices but no
  # arm64-simulator. The onnxruntime-c pod provides an XCFramework.
  s.vendored_frameworks = 'Frameworks/opencv2.framework'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE'                       => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD'          => 'c++14',
    'CLANG_CXX_LIBRARY'                    => 'libc++',
    'HEADER_SEARCH_PATHS'                  => [
      '"$(PODS_TARGET_SRCROOT)/Frameworks"',
      '"$(PODS_ROOT)/Headers/Public/onnxruntime-c"',
    ].join(' '),
    'GCC_PREPROCESSOR_DEFINITIONS'         => 'TARGET_IOS=1',
    # opencv2.framework is missing an arm64-simulator slice; fall back to
    # Rosetta (x86_64) on Apple Silicon simulators.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64',
  }
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64',
  }
end
