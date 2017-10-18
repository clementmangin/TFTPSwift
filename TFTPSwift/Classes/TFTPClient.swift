//
//  TFTPClient.swift
//  Smartika
//
//  Created by Clément Mangin on 2017-10-18.
//  Copyright © 2017 Clément Mangin. All rights reserved.
//

import Foundation
import CocoaAsyncSocket

private let errorDomain = "com.smartika.TFTPClient.ErrorDomain"

enum TFTPTransmissionMode: String {
    case Octet = "octet"
    case NetAscii = "netascii"
    case Mail = "mail"
}

protocol TFTPClientDelegate: class {
    func tftpClientWillSendRequest(_ tftpClient: TFTPClient)
    func tftpClientDidSendRequest(_ tftpClient: TFTPClient)
    func tftpClientDidReceiveAckForRequest(_ tftpClient: TFTPClient)
    func tftpClient(_ tftpClient: TFTPClient, willSendDataBlock block: UInt16)
    func tftpClient(_ tftpClient: TFTPClient, didSendDataBlock block: UInt16)
    func tftpClient(_ tftpClient: TFTPClient, willReceiveAckForDataBlock block: UInt16)
    func tftpClient(_ tftpClient: TFTPClient, didReceiveAckForDataBlock block: UInt16)
    func tftpClient(_ tftpClient: TFTPClient, didFailWithError error: Error)
    func tftpClient(_ tftpClient: TFTPClient, didSendFile: String, withName: String)
    func tftpClient(_ tftpClient: TFTPClient, willSendBytes sentBytes: UInt64, outOfBytes totalBytes: UInt64)
    func tftpClient(_ tftpClient: TFTPClient, didSendBytes sentBytes: UInt64, outOfBytes totalBytes: UInt64)
}

// Provide default no-op implementation for TFTPClientDelegate protocol
extension TFTPClientDelegate {
    func tftpClientWillSendRequest(_ tftpClient: TFTPClient) { }
    func tftpClientDidSendRequest(_ tftpClient: TFTPClient) { }
    func tftpClientDidReceiveAckForRequest(_ tftpClient: TFTPClient) { }
    func tftpClient(_ tftpClient: TFTPClient, willSendDataBlock block: UInt16) { }
    func tftpClient(_ tftpClient: TFTPClient, didSendDataBlock block: UInt16) { }
    func tftpClient(_ tftpClient: TFTPClient, willReceiveAckForDataBlock block: UInt16) { }
    func tftpClient(_ tftpClient: TFTPClient, didReceiveAckForDataBlock block: UInt16) { }
    func tftpClient(_ tftpClient: TFTPClient, didFailWithError error: Error) { }
    func tftpClient(_ tftpClient: TFTPClient, didSendFile: String, withName: String) { }
    func tftpClient(_ tftpClient: TFTPClient, willSendBytes sentBytes: UInt64, outOfBytes totalBytes: UInt64) { }
    func tftpClient(_ tftpClient: TFTPClient, didSendBytes sentBytes: UInt64, outOfBytes totalBytes: UInt64) { }
}

class TFTPClient: NSObject {
    
    weak var delegate: TFTPClientDelegate?
    fileprivate var delegateQueue: DispatchQueue
    
    let blockSize: UInt = 512
    
    var isReady: Bool {
        return !running
    }
    
    fileprivate var running = false
    fileprivate var lastBlockSent = false
    
    // MARK: Private methods
    
    fileprivate static let writeRequestPacketTag = 0
    
    // Client-dependent
    fileprivate var host: String!
    fileprivate var port: UInt16
    fileprivate var address: Data?
    
    // TODO make all this configurable
    fileprivate var timeout: TimeInterval = 5.0
    fileprivate var timeoutBlock: dispatch_cancelable_closure?
    fileprivate var timeoutCount = 0
    fileprivate let maxTimeoutCount = 3
    
    // Operation-dependent
    fileprivate var path: String!
    fileprivate var file: FileHandle?
    fileprivate var fileSize: UInt64 = 0
    fileprivate var name: String?
    fileprivate var mode: TFTPTransmissionMode?
    fileprivate var socket: GCDAsyncUdpSocket?
    fileprivate var lastBlockNumber: UInt16 = 0
    
    /**
     Instantiate a TFTP client.
     Connection to remote host is established when files are sent.
     - parameter host: remote host name or IP address.
     - parameter port: remote host TFTP server port (defaults to TFTP default port 69).
     */
    init(host: String!, port: UInt16 = 69, delegate: TFTPClientDelegate? = nil, delegateQueue: DispatchQueue? = nil) {
        self.host = host
        self.port = port
        self.delegate = delegate
        self.delegateQueue = delegateQueue ?? DispatchQueue(label: "TFTPClient", attributes: [])
        super.init()
    }
    
    /**
     Send the given file to the remote host configured at the client's instantiation,
     using the given name and transmission mode for the transfer.
     Client must be ready to starts a new operation (that is, it must not be performing another operation).
     
     - parameter path: Path to the local file to send.
     - parameter name: Name the file should be given on the remote host.
     - parameter mode: Transmission mode (see https://tools.ietf.org/html/rfc1350 for a description). Defaults to TFTPTransmissionMode.Octet.
     
     - throws: If file cannot be opened or connection to remote host cannot be established.
     */
    func sendFile(_ path: String!, name: String!, mode: TFTPTransmissionMode = .Octet) throws {
        guard isReady else {
            let error = NSError(domain: errorDomain, code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Could not send file (client is already running)",
                NSLocalizedFailureReasonErrorKey: "Client is already running"
                ])
            delegate?.tftpClient(self, didFailWithError: error)
            return
        }
        self.running = true
        self.mode = mode
        self.name = name
        self.path = path
        self.file = FileHandle(forReadingAtPath: path)
        do {
            let attr: NSDictionary? = try FileManager.default.attributesOfItem(atPath: path) as NSDictionary?
            if let _attr = attr {
                fileSize = _attr.fileSize();
            }
        } catch {
            delegate?.tftpClient(self, didFailWithError: error)
            cancel()
            return
        }
        try self.connect()
    }
    
    func cancel() {
        cleanup()
    }
    
    /**
     Create a UDP socket ready to send data to and receive data from the remote host.
     File upload starts as soon as the connection is established.
     */
    fileprivate func connect() throws {
        socket = GCDAsyncUdpSocket(delegate: self, delegateQueue: delegateQueue)
        try socket?.bind(toPort: 0)
        try socket?.beginReceiving()
        
        socket?.setReceiveFilter({ [weak self] (data: Data?, address: Data?, context: AutoreleasingUnsafeMutablePointer<AnyObject?>?) -> Bool in
            // Check remote address if connection is established
            if let localAddress = self?.address {
                guard address == localAddress else {
                    return false
                }
            }
            
            // Filter TFTP packets
            guard let packet = TFTPacketFactory.deserialize(data) else {
                return false
            }
            
            // Set TFTP packet in receiver context
            context?.pointee = packet
            
            return true
        }, with: delegateQueue)
        
        sendWriteRequest()
    }
    
    /**
     Close the socket.
     */
    fileprivate func closeSocket() {
        if let socket = socket {
            if socket.isConnected() {
                socket.close()
            }
        }
    }
    
    /**
     Close the local file handle.
     */
    fileprivate func closeFile() {
        if let file = file {
            file.closeFile()
        }
    }
    
    /**
     Clean up all resources (opened socket and files) and ready client for new operations.
     */
    fileprivate func cleanup() {
        cancel_delay(timeoutBlock)
        closeSocket()
        closeFile()
        address = nil
        running = false
    }
    
    fileprivate func sendWriteRequest() {
        delegate?.tftpClientWillSendRequest(self)
        
        let request = TFTPWriteRequest(name: name ?? "", mode: mode!)
        socket!.send(request.serialize() as Data, toHost: host, port: port, withTimeout: -1, tag: TFTPClient.writeRequestPacketTag)
        
        lastBlockNumber = 0
        
        // Prepare to resend block after timeout (or fail if max. number of retries is reached)
        timeoutBlock = delay(timeout) { [weak self] in
            guard let s = self else { return }
            s.timeoutCount += 1
            if s.timeoutCount > s.maxTimeoutCount {
                s.failWithError(100, message: "Timeout")
                s.cleanup()
            } else {
                s.sendWriteRequest()
            }
        }
    }
}

extension TFTPClient: GCDAsyncUdpSocketDelegate {
    
    fileprivate func failWithError(_ code: Int, message: String) {
        let error = NSError(domain: errorDomain, code: code, userInfo: [
            NSLocalizedDescriptionKey: message,
            NSLocalizedFailureReasonErrorKey: message
            ])
        delegate?.tftpClient(self, didFailWithError: error)
        cleanup()
    }
    
    fileprivate func sendBlock(_ block: UInt16) {
        
        // Make sure we are at the right offset in the file
        let offset: UInt64 = UInt64(block - 1) * 512
        if file!.offsetInFile != offset {
            file!.seek(toFileOffset: offset)
        }
        
        // Read block in file
        let data = file!.readData(ofLength: Int(blockSize))
        
        // If we read something or we just reached the end of the file
        
        guard data.count != 0 || fileSize % UInt64(blockSize) == 0 && UInt64(block) == fileSize / UInt64(blockSize) else {
            failWithError(101, message: "Failed to read file")
            return
        }
        
        let dataPacket = TFTPData(block: block, data: data)
        delegate?.tftpClient(self, willSendDataBlock: block)
        delegate?.tftpClient(self, willSendBytes: UInt64(UInt(block) * blockSize), outOfBytes: fileSize)
        
        socket!.send(dataPacket.serialize(), toAddress: self.address!, withTimeout: -1, tag: Int(block))
        
        lastBlockNumber = block
        
        // Prepare to resend block after timeout (or fail if max. number of retries is reached)
        timeoutBlock = delay(timeout) { [weak self] in
            guard let s = self else { return }
            s.timeoutCount += 1
            if s.timeoutCount > s.maxTimeoutCount {
                s.failWithError(100, message: "Timeout")
                s.cleanup()
            } else {
                s.sendBlock(block)
            }
        }
        
        if data.count < Int(blockSize) {
            lastBlockSent = true
        }
    }
    
    func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        
        // Read packet
        guard let packet = filterContext as? TFTPPacket else {
            failWithError(102, message: "Invalid packet received")
            return
        }
        
        guard packet is TFTPAcknowledgement || packet is TFTPError else {
            failWithError(103, message: "Unsupported packet received")
            return
        }
        
        // If packet is error, interrupt operation
        if let packet = packet as? TFTPError {
            failWithError(Int(packet.code), message: packet.message)
            
            // If packet is acknowledgement, continue operation
        } else if let packet = packet as? TFTPAcknowledgement {
            var block = packet.block
            
            guard lastBlockNumber == packet.block else {
                return
            }
            
            cancel_delay(timeoutBlock)
            timeoutCount = 0
            
            if block == 0 {
                delegate?.tftpClientDidReceiveAckForRequest(self)
                // Store remote address for filtering of future packets
                self.address = address
            } else {
                delegate?.tftpClient(self, didReceiveAckForDataBlock: block)
                delegate?.tftpClient(self, didSendBytes: UInt64(UInt(block) * blockSize), outOfBytes: fileSize)
            }
            
            if lastBlockSent {
                // Last block acknowledgement received, operation is completed
                delegate?.tftpClient(self, didSendFile: self.path, withName: self.name!)
                cleanup()
            } else {
                block += 1
                sendBlock(block)
            }
        }
    }
    
    func udpSocket(_ sock: GCDAsyncUdpSocket, didSendDataWithTag tag: Int) {
        // Notify delegate for every successfuly sent packet
        if tag == TFTPClient.writeRequestPacketTag {
            delegate?.tftpClientDidSendRequest(self)
        } else {
            delegate?.tftpClient(self, didSendDataBlock: UInt16(tag))
        }
    }
    
    func udpSocket(_ sock: GCDAsyncUdpSocket, didNotSendDataWithTag tag: Int, dueToError error: Error?) {
        // Notify delegate for every failure
        if error != nil {
            delegate?.tftpClient(self, didFailWithError: error!)
        }
        // Terminate operation
        self.cleanup()
    }
    
    func udpSocketDidClose(_ sock: GCDAsyncUdpSocket, withError error: Error?) {
        // Notify delegate if socket was closed upon error
        if error != nil {
            delegate?.tftpClient(self, didFailWithError: error!)
        }
        // Terminate operation
        self.cleanup()
    }
    
    func udpSocket(_ sock: GCDAsyncUdpSocket, didNotConnect error: Error?) {
        // Notify delegate if socket could not connect to remote host
        if error != nil {
            delegate?.tftpClient(self, didFailWithError: error!)
        }
        // Terminate operation
        self.cleanup()
    }
}
