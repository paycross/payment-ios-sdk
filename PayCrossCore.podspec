Pod::Spec.new do |s|
  s.name             = 'PayCrossCore'
  s.version          = '0.8.1'
  s.summary          = 'Platform-agnostic core of the PayCross iOS SDK.'
  s.description      = <<-DESC
    The payment state machine, wire models, JWT decoding, card validation and 3DS
    navigation rules. Free of UIKit, SwiftUI and WebKit by design so it builds and
    tests on Linux; the UI layer lives in the PayCross pod.
  DESC
  s.homepage         = 'https://github.com/paycross/payment-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = 'PayCross'

  s.source           = {
    :git => 'https://github.com/paycross/payment-ios-sdk.git',
    :tag => "v#{s.version}"
  }

  # Must match Package.swift's platforms:, or CocoaPods fails to resolve instead of reporting the version.
  s.ios.deployment_target = '16.0'

  # .swiftLanguageMode(.v6) is not carried into a Pods project, so the Swift 6 mode is pinned here.
  s.swift_versions = ['6.0']
  # Both pods compile as one Swift package so package-access symbols in Core stay usable by PayCross.
  s.pod_target_xcconfig = { 'SWIFT_VERSION' => '6.0', 'OTHER_SWIFT_FLAGS' => '-package-name PayCross' }

  s.source_files = 'Sources/PayCrossCore/**/*.swift'

  # Apple requires SDKs to ship a privacy manifest in a bundle named after the pod.
  s.resource_bundles = { 'PayCrossCorePrivacy' => ['Sources/PayCrossCore/Resources/PrivacyInfo.xcprivacy'] }
end
