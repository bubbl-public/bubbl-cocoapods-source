Pod::Spec.new do |s|
  s.name = 'BubblReactNativeSdk'
  s.version = '3.1.4'
  s.summary = 'React Native wrapper for Bubbl SDK v3 native Android and iOS cores.'
  s.homepage = 'https://bubbl.tech'
  s.license = { :type => 'Commercial', :text => 'Copyright Bubbl. All rights reserved.' }
  s.author = { 'Bubbl' => 'engineering@bubbl.tech' }
  s.source = { :git => 'https://github.com/bubbl-platform/renewed-sdk.git', :tag => s.version.to_s }

  s.platform = :ios, '15.0'
  s.swift_version = '5.9'
  s.source_files = 'ios/**/*.{h,m,mm,swift}'
  s.static_framework = true

  s.dependency 'React-Core'
  s.dependency 'BubblSDK', '3.1.4'
end
