Pod::Spec.new do |s|
  s.name             = 'PayCross'
  s.version          = '0.1.0'
  s.summary          = 'PayCross iOS payment SDK.'
  s.description      = <<-DESC
    Drop-in card payment sheet: card entry, saved cards, 3D Secure v2 and status
    polling, presented from a view controller and resolving to a single result.
  DESC
  s.homepage         = 'https://github.com/paycross/payment-ios-sdk'
  s.license          = { :type => 'Proprietary', :text => 'Copyright PayCross. All rights reserved.' }
  s.author           = 'PayCross'

  s.source           = {
    :git => 'https://github.com/paycross/payment-ios-sdk.git',
    :tag => "v#{s.version}"
  }

  s.ios.deployment_target = '16.0'

  s.swift_versions = ['6.0']
  s.pod_target_xcconfig = { 'SWIFT_VERSION' => '6.0' }

  s.source_files = 'Sources/PayCross/**/*.swift'
  s.frameworks   = 'UIKit', 'SwiftUI', 'WebKit'

  # Exact, not optimistic: the two pods are cut from one tag and one repo, so a
  # merchant resolving PayCross 0.1.0 against PayCrossCore 0.2.0 is never a
  # combination anyone built or tested.
  s.dependency 'PayCrossCore', "#{s.version}"
end
