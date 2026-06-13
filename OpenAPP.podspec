Pod::Spec.new do |s|
  s.name             = 'OpenAPP'
  s.version          = '0.1.0'
  s.summary          = 'An embedded AI agent SDK for iOS and macOS.'
  s.description      = <<-DESC
    OpenAPP is a Swift framework that provides a complete agent loop for
    LLM-powered applications. It includes tool registration, multi-session
    management, streaming responses, memory, skills, and an optional UIKit
    overlay UI.
  DESC

  s.homepage         = 'https://github.com/chbo297/OpenAPP'
  s.license          = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author           = { 'OpenAPP Contributors' => '' }
  s.source           = { :git => 'https://github.com/chbo297/OpenAPP.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '12.0'
  s.swift_version    = '5.10'

  s.source_files     = 'Sources/**/*.swift'
  s.ios.frameworks   = 'UIKit', 'AVFoundation'
  s.osx.frameworks   = 'AppKit', 'AVFoundation'
end
