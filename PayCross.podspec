Pod::Spec.new do |s|
  s.name             = 'PayCross'
  s.version          = '0.8.1'
  s.summary          = 'PayCross iOS payment SDK.'
  s.description      = <<-DESC
    Drop-in card payment sheet: card entry, saved cards, 3D Secure v2 and status
    polling, presented from a view controller and resolving to a single result.
  DESC
  s.homepage         = 'https://github.com/paycross/payment-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = 'PayCross'

  s.source           = {
    :git => 'https://github.com/paycross/payment-ios-sdk.git',
    :tag => "v#{s.version}"
  }

  s.ios.deployment_target = '16.0'

  s.swift_versions = ['6.0']
  # Both pods compile as one Swift package so package-access symbols in Core stay usable by PayCross.
  s.pod_target_xcconfig = { 'SWIFT_VERSION' => '6.0', 'OTHER_SWIFT_FLAGS' => '-package-name PayCross' }

  s.source_files = 'Sources/PayCross/**/*.swift'
  s.frameworks   = 'UIKit', 'SwiftUI', 'WebKit', 'PassKit'

  # Apple requires SDKs to ship a privacy manifest in a bundle named after the pod.
  s.resource_bundles = {
    'PayCrossPrivacy' => ['Sources/PayCross/Resources/PrivacyInfo.xcprivacy'],
    'PayCrossLocalizations' => ['Sources/PayCross/Resources/*.lproj']
  }

  # Exact pin: both pods ship from one tag, so only matching versions are valid together.
  s.dependency 'PayCrossCore', "#{s.version}"
end
