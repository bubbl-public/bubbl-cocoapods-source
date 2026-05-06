Pod::Spec.new do |s|
  s.name = 'Bubbl-Sdk'
  s.version = '3.0.0-beta.1'
  s.summary = 'Compatibility CocoaPods alias for the Bubbl v3 iOS SDK.'
  s.description = 'Bubbl-Sdk keeps the legacy CocoaPods package identity available while depending on the v3 BubblSDK pod.'
  s.homepage = 'https://bubbl.tech'
  s.license = { :type => 'Commercial', :text => 'Copyright Bubbl. All rights reserved.' }
  s.author = { 'Bubbl' => 'engineering@bubbl.tech' }
  s.source = { :git => 'https://github.com/bubbl-repo/renewed-sdk.git', :tag => s.version.to_s }

  s.platform = :ios, '15.0'
  s.swift_version = '5.9'
  s.static_framework = true
  s.dependency 'BubblSDK', s.version.to_s
end
