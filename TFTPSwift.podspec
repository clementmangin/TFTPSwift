#
# Be sure to run `pod lib lint TFTPSwift.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'TFTPSwift'
  s.version          = '0.1.0'
  s.summary          = 'A TFTP client library written in Swift.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
TFTPSwift is a TFTP client library written in Swift 
that aims to be a working implementation of TFTP client 
as per RFC 1350. For nnow, only support sending files 
to a TFTP server.
                       DESC

  s.homepage         = 'https://github.com/clementmangin/TFTPSwift'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Clément Mangin' => 'clement.mangin@gmail.com' }
  s.source           = { :git => 'https://github.com/clementmangin/TFTPSwift.git', :tag => s.version.to_s }
  
  s.osx.deployment_target = '10.11'
  s.ios.deployment_target = '8.0'

  s.source_files = 'TFTPSwift/Classes/**/*'

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  s.dependency 'CocoaAsyncSocket', '~> 7.6'
end
