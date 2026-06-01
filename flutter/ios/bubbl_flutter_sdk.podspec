Pod::Spec.new do |s|
  s.name = 'bubbl_flutter_sdk'
  s.version = '3.0.4'
  s.summary = 'Flutter wrapper for Bubbl SDK v3 native Android and iOS cores.'
  s.description = 'Bubbl Flutter SDK bridges the platform-neutral Dart facade to the native Bubbl Android and iOS SDK runtimes.'
  s.homepage = 'https://bubbl.tech'
  s.license = { :type => 'Commercial', :text => 'Copyright Bubbl. All rights reserved.' }
  s.author = { 'Bubbl' => 'engineering@bubbl.tech' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'BubblSDK', '3.0.4'
  s.platform = :ios, '15.0'
  s.swift_version = '5.9'
  s.static_framework = true
end
