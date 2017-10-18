//
//  TFTPPacket.swift
//  Smartika
//
//  Created by Clément Mangin on 2017-10-18.
//  Copyright © 2017 Clément Mangin. All rights reserved.
//

import Foundation

/**
 Set of operations supported by the TFTP protocol.
 Correspond to the TFTP opcodes defined in RFC 1350.
 */
enum TFTPOperation: UInt16 {
    case readRequest = 1
    case writeRequest = 2
    case data = 3
    case acknowledgement = 4
    case error = 5
}


/**
 TFTP packet, composed of a two-bytes opcode (see TFTPOperation).
 */
protocol TFTPPacket: class {
    var opcode: TFTPOperation { get }
    
    /**
     Serialize a TFTPPacket into bytes bundled in a NSData object.
     */
    func serialize() -> Data
}

private extension TFTPPacket {
    
    func serializeOpCode() -> [UInt8] {
        let result: [UInt8] = [UInt8(opcode.rawValue >> 8 & 0xff), UInt8(opcode.rawValue & 0xff)]
        return result
    }
}

internal struct TFTPacketFactory {
    
    /**
     Deserialize data into a TFTPPacket object of the corresponding type.
     The given data must corresponds to the packet payload, excluding the two-bytes opcode, which should be read prior to calling
     the deserialize method on the proper struct implementing this protocol.
     
     - parameter data: the data received from the server, excluding the first two-bytes (opcode).
     
     - returns: A TFTPPacket object corresponding to the received data.
     */
    static func deserialize(_ data: Data!) -> TFTPPacket? {
        // Read opcode
        let opcode = data.withUnsafeBytes { (ptr: UnsafePointer<UInt16>) -> UInt16 in
            return CFSwapInt16BigToHost(ptr.pointee)
        }
        // Deserialize packet accordingly
        if let operation = TFTPOperation(rawValue: opcode) {
            let subdata =  data.subdata(in: 2..<data.count)
            switch operation {
            case .acknowledgement:
                return TFTPAcknowledgement.deserialize(subdata)
            case .error:
                return TFTPError.deserialize(subdata)
            default:
                // Not supported
                break
            }
        }
        return nil
    }
}

/**
 TFTP write request packet
 */
class TFTPWriteRequest: TFTPPacket {
    var opcode: TFTPOperation { return .writeRequest }
    var name: String!
    var mode: TFTPTransmissionMode
    
    init(name: String!, mode: TFTPTransmissionMode) {
        self.name = name
        self.mode = mode
    }
    
    func serialize() -> Data {
        // Write opcode
        var bytes = self.serializeOpCode()
        // Write null-terminated name string
        bytes.append(contentsOf: name.utf8CString.map { UInt8($0) })
        // Write null-terminated transmission mode string
        bytes.append(contentsOf: mode.rawValue.utf8CString.map { UInt8($0) })
        return Data(bytes: UnsafePointer<UInt8>(bytes), count: bytes.count)
    }
    
    typealias T = TFTPWriteRequest
    static func deserialize(_ data: Data!) -> TFTPWriteRequest {
        fatalError("Not supported")
    }
}

/**
 TFTP data packet
 */
class TFTPData: TFTPPacket {
    var opcode: TFTPOperation { return .data }
    var block: UInt16
    var data: Data!
    
    init(block: UInt16, data: Data!) {
        self.block = block
        self.data = data
    }
    
    func serialize() -> Data {
        // Write opcode
        var bytes = self.serializeOpCode()
        // Write block #
        bytes.append(contentsOf: [UInt8(block >> 8 & 0xff), UInt8(block & 0xff)])
        // Write block
        let result = NSMutableData(bytes: bytes, length: bytes.count)
        result.append(data)
        return result as Data
    }
    
    typealias T = TFTPData
    static func deserialize(_ data: Data!) -> TFTPData {
        fatalError("Not supported")
    }
}

/**
 TFTP acknowledgement packet
 */
class TFTPAcknowledgement: TFTPPacket {
    var opcode: TFTPOperation { return .acknowledgement }
    var block: UInt16
    
    init(block: UInt16) {
        self.block = block
    }
    
    func serialize() -> Data {
        // Write opcode
        var bytes = self.serializeOpCode()
        // Write block #
        bytes.append(contentsOf: [UInt8(block >> 8 & 0xff), UInt8(block & 0xff)])
        return Data(bytes: UnsafePointer<UInt8>(bytes), count: bytes.count)
    }
    
    typealias T = TFTPAcknowledgement
    static func deserialize(_ data: Data!) -> TFTPAcknowledgement {
        let block = data.withUnsafeBytes { (ptr: UnsafePointer<UInt16>) -> UInt16 in
            return CFSwapInt16BigToHost(ptr.pointee)
        }
        return TFTPAcknowledgement(block: block)
    }
}

/**
 TFTP error packet
 */
class TFTPError: TFTPPacket {
    var opcode: TFTPOperation { return .error }
    var code: UInt16
    var message: String!
    
    init(code: UInt16,  message: String!) {
        self.code = code
        self.message = message
    }
    
    func serialize() -> Data {
        // Write opcode
        var bytes = self.serializeOpCode()
        // Write error code
        bytes.append(contentsOf: [UInt8(code >> 8 & 0xff), UInt8(code & 0xff)])
        // Write error code
        bytes.append(contentsOf: message.utf8CString.map { (c: Int8) -> UInt8 in UInt8(c) })
        return Data(bytes: UnsafePointer<UInt8>(bytes), count: bytes.count)
    }
    
    typealias T = TFTPError
    static func deserialize(_ data: Data!) -> TFTPError {
        let code: UInt16 = data.withUnsafeBytes { (ptr: UnsafePointer<UInt16>) -> UInt16 in
            return CFSwapInt16BigToHost(ptr.pointee)
        }
        let messageData = data.subdata(in: 2..<(data.count - 1)) // remove last null byte
        let message = String(data: messageData, encoding: String.Encoding.utf8)
        return TFTPError(code: code, message: message)
    }
}
