#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'on_device_ai'
  s.version          = '0.0.1'
  s.summary          = 'On-device AI bridge for Tri Flash'
  s.description      = 'On-device AI bridge using Apple Foundation Models when available.'
  s.homepage         = 'https://github.com/triflash/tri_flash'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Tri Flash' => 'dev@triflash.app' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
  s.weak_frameworks = 'FoundationModels'
end
