Pod::Spec.new do |s|
  s.name             = 'OpenAPP'
  s.version          = '0.1.0'
  s.summary          = 'A provider-agnostic AI agent framework for iOS.'
  s.description      = <<-DESC
    OpenAPP is a Swift framework that provides a complete agent loop for
    LLM-powered applications. It includes tool registration, multi-session
    management, streaming responses, and an optional chat UI layer.
  DESC

  s.homepage         = 'https://github.com/user/OpenAPP'
  s.license          = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author           = { 'OpenAPP Contributors' => '' }
  s.source           = { :git => 'https://github.com/user/OpenAPP.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version    = '5.0'

  s.source_files     = 'Sources/OpenAPP/**/*.swift'
  s.frameworks       = 'Foundation', 'UIKit'
end
