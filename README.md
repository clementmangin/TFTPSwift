# TFTPSwift

[![Version](https://img.shields.io/cocoapods/v/TFTPSwift.svg?style=flat)](http://cocoapods.org/pods/TFTPSwift)
[![License](https://img.shields.io/cocoapods/l/TFTPSwift.svg?style=flat)](http://cocoapods.org/pods/TFTPSwift)
[![Platform](https://img.shields.io/cocoapods/p/TFTPSwift.svg?style=flat)](http://cocoapods.org/pods/TFTPSwift)

TFTPSwift is a TFTP client library written in Swift that aims to be a working implementation of TFTP client as per RFC 1350. For nnow, only support sending files to a TFTP server.

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

TFTPSwift depends on [CocoaAsyncSocket](https://github.com/robbiehanson/CocoaAsyncSocket) for UDP sockets.

## Installation

TFTPSwift is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'TFTPSwift'
```

## Limitations

TFTPSwift can only send files, but cannot download them yet.

## Author

Clément Mangin, clement.mangin@gmail.com

## License

TFTPSwift is available under the MIT license. See the LICENSE file for more info.
