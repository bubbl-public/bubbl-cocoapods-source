Pod::Spec.new do |s|
  s.name = 'BubblSDK'
  s.version = '3.0.4'
  s.summary = 'Native iOS SDK for Bubbl v3 runtime, geofence, notification, and ingest flows.'
  s.homepage = 'https://bubbl.tech'
  s.license = { :type => 'Commercial', :text => 'Copyright Bubbl. All rights reserved.' }
  s.author = { 'Bubbl' => 'engineering@bubbl.tech' }
  s.source = { :git => 'https://github.com/bubbl-public/bubbl-cocoapods-source.git', :tag => '3.0.4' }

  s.platform = :ios, '15.0'
  s.swift_version = '5.9'
  s.source_files = [
    'ios/Sources/BubblSDK/**/*.swift',
    'Sources/BubblSDK/**/*.swift'
  ]
  s.frameworks = 'CoreLocation', 'UserNotifications', 'UIKit'
  s.library = 'sqlite3'
  s.static_framework = true
end
