Pod::Spec.new do |s|
  s.name             = 'echoes_eq'
  s.version          = '0.0.1'
  s.summary          = 'ECHOES 10-band equalizer for iOS'
  s.description      = 'Peaking-EQ biquads applied to AVPlayer items through MTAudioProcessingTap.'
  s.homepage         = 'https://github.com/padr0chill/zhopa-mobile'
  s.license          = { :type => 'MIT' }
  s.author           = { 'ECHOES' => 'echoes@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.frameworks       = 'AVFoundation', 'MediaToolbox', 'AudioToolbox', 'CoreMedia'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end