Pod::Spec.new do |s|
  s.name             = 'PayCrossCore'
  s.version          = '0.5.0'
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

  # Must track Package.swift's platforms:. A mismatch surfaces to the merchant as
  # an opaque CocoaPods resolution failure rather than a clear minimum-version error.
  s.ios.deployment_target = '16.0'

  # .swiftLanguageMode(.v6) is a SwiftPM setting and is not carried into a Pods
  # project, so the sources would silently build in Swift 5 mode. The strict
  # concurrency this SDK is written against is not optional, so pin it here too.
  s.swift_versions = ['6.0']
  # Both pods must compile as one Swift package so `package`-access symbols in
  # Core stay invisible to merchants but usable by PayCross.
  s.pod_target_xcconfig = { 'SWIFT_VERSION' => '6.0', 'OTHER_SWIFT_FLAGS' => '-package-name PayCross' }

  s.source_files = 'Sources/PayCrossCore/**/*.swift'

  # Apple requires SDKs to ship a privacy manifest; CocoaPods/Apple guidance is
  # to place it in a resource bundle named after the pod so the built app gets
  # a PayCrossCorePrivacy.bundle/PrivacyInfo.xcprivacy Apple's tooling expects.
  s.resource_bundles = { 'PayCrossCorePrivacy' => ['Sources/PayCrossCore/Resources/PrivacyInfo.xcprivacy'] }
end
