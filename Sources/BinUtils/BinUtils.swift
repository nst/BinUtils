//
//  BinUtils.swift
//  BinUtils
//
//  Created by Nicolas Seriot on 12/03/16.
//  Copyright © 2016 Nicolas Seriot. All rights reserved.
//

import Foundation
import CoreFoundation

// MARK: protocol UnpackedType

public protocol Unpackable {}

extension NSString: Unpackable {}
extension Bool: Unpackable {}
extension Int: Unpackable {}
extension UInt: Unpackable {}
extension Double: Unpackable {}

// MARK: protocol DataConvertible

protocol DataConvertible {}

extension DataConvertible {

    init?(data: Data) {
        guard data.count == MemoryLayout<Self>.size else { return nil }
        self = data.withUnsafeBytes { $0.load(as: Self.self) }
    }

    init?(bytes: [UInt8]) {
        let data = Data(bytes)
        self.init(data:data)
    }

    var data: Data {
        var value = self
        return withUnsafePointer(to: &value) { Data(bytes: UnsafePointer($0), count: MemoryLayout<Self>.size) }
    }
}

extension Bool : DataConvertible { }

extension Int8 : DataConvertible { }
extension Int16 : DataConvertible { }
extension Int32 : DataConvertible { }
extension Int64 : DataConvertible { }

extension UInt8 : DataConvertible { }
extension UInt16 : DataConvertible { }
extension UInt32 : DataConvertible { }
extension UInt64 : DataConvertible { }

extension Float32 : DataConvertible { }
extension Float64 : DataConvertible { }

// MARK: String extension

extension String {
    // NOTE: uses UTF-16 (NSRange) semantics, so the indices are only meaningful
    // for ASCII content. It is file-private because it is solely a helper for
    // unhexlify(), which operates on validated hexadecimal (ASCII) strings.
    fileprivate subscript (from:Int, to:Int) -> String {
        return NSString(string: self).substring(with: NSMakeRange(from, to-from))
    }
}

// MARK: Data extension

extension Data {
    var bytes : [UInt8] {
        return [UInt8](self)
    }
}

// MARK: functions

public func hexlify(_ data:Data) -> String {

    // similar to hexlify() in Python's binascii module
    // https://docs.python.org/2/library/binascii.html

    return data.map { String(format: "%02x", $0) }.joined()
}

public func unhexlify(_ string:String) -> Data? {

    // similar to unhexlify() in Python's binascii module
    // https://docs.python.org/2/library/binascii.html

    let s = string.uppercased().replacingOccurrences(of: " ", with: "")

    if s.count % 2 != 0 {
        print("-- odd-length string")
        return nil
    }

    let nonHexCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEF").inverted
    if let range = s.rangeOfCharacter(from: nonHexCharacterSet) {
        print("-- found non hex character at range \(range)")
        return nil
    }

    var data = Data(capacity: s.count / 2)

    for i in stride(from: 0, to:s.count, by:2) {
        let byteString = s[i, i+2]
        let byte = UInt8(byteString.withCString { strtoul($0, nil, 16) })
        data.append([byte] as [UInt8], count: 1)
    }

    return data
}

// If `c` is a decimal digit, accumulate it into the repeat counter `n` and
// return true; otherwise leave `n` untouched and return false. Shared by
// numberOfBytesInFormat(), pack() and unpack() so the parsing stays in sync.
func parseRepeatCountDigit(_ c:Character, into n:inout Int) -> Bool {
    guard let i = Int(String(c)), 0...9 ~= i else { return false }
    if n > 0 { n *= 10 }
    n += i
    return true
}

func readIntegerType<T:DataConvertible>(_ type:T.Type, bytes:[UInt8], loc:inout Int) -> T {
    let size = MemoryLayout<T>.size
    let sub = Array(bytes[loc..<(loc+size)])
    loc += size
    return T(bytes: sub)!
}

func readFloatingPointType<T:DataConvertible>(_ type:T.Type, bytes:[UInt8], loc:inout Int, isBigEndian:Bool) -> T {
    let size = MemoryLayout<T>.size
    let sub = Array(bytes[loc..<(loc+size)])
    loc += size
    let sub_ = isBigEndian ? sub.reversed() : sub
    return T(bytes: sub_)!
}

func isBigEndianFromMandatoryByteOrderFirstCharacter(_ format:String) -> Bool {

    guard let firstChar = format.first else { assertionFailure("empty format"); return false }

    let s = NSString(string: String(firstChar))
    let c = s.substring(to: 1)

    if c == "@" { assertionFailure("native size and alignment is unsupported") }

    if c == "=" || c == "<" { return false }
    if c == ">" || c == "!" { return true }

    assertionFailure("format '\(format)' first character must be among '=<>!'")

    return false
}

// akin to struct.calcsize(fmt)
func numberOfBytesInFormat(_ format:String) -> Int {

    var numberOfBytes = 0

    var n = 0 // repeat counter

    var mutableFormat = format

    while !mutableFormat.isEmpty {

        let c = mutableFormat.remove(at: mutableFormat.startIndex)

        if parseRepeatCountDigit(c, into:&n) { continue }

        if c == "s" {
            numberOfBytes += max(n,1)
            n = 0
            continue
        }

        let repeatCount = max(n,1)

        switch(c) {

        case "@", "<", "=", ">", "!", " ":
            ()
        case "c", "b", "B", "x", "?":
            numberOfBytes += 1 * repeatCount
        case "h", "H":
            numberOfBytes += 2 * repeatCount
        case "i", "l", "I", "L", "f":
            numberOfBytes += 4 * repeatCount
        case "q", "Q", "d":
            numberOfBytes += 8 * repeatCount
        case "P":
            numberOfBytes += MemoryLayout<Int>.size * repeatCount
        default:
            assertionFailure("-- unsupported format \(c)")
        }

        n = 0
    }

    return numberOfBytes
}

func formatDoesMatchDataLength(_ format:String, data:Data) -> Bool {
    let sizeAccordingToFormat = numberOfBytesInFormat(format)
    let dataLength = data.count
    if sizeAccordingToFormat != dataLength {
        print("format \"\(format)\" expects \(sizeAccordingToFormat) bytes but data is \(dataLength) bytes")
        return false
    }

    return true
}

/*
 pack() and unpack() should behave as Python's struct module https://docs.python.org/2/library/struct.html BUT:
 - native size and alignment '@' is not supported
 - as a consequence, the byte order specifier character is mandatory and must be among "=<>!"
 - native byte order '=' assumes a little-endian system (eg. Intel x86)
 - Pascal strings 'p' and native pointers 'P' are not supported
 */

public enum BinUtilsError: Error {
    case formatDoesMatchDataLength(format:String, dataSize:Int)
    case unsupportedFormat(character:Character)
    case emptyFormat
    case invalidByteOrder(character:Character)
    case missingObject(format:Character)
    case wrongObjectType(format:Character)
    case stringEncodingError(string:String, encoding:String.Encoding)
}

// 'Q' (unsigned long long) accepts either an Int or a UInt object so that the
// full UInt64 range can be packed and round-trips with unpack()
func uint64Value(_ o:Any, _ c:Character) throws -> UInt64 {
    if let u = o as? UInt { return UInt64(u) }
    guard let i = o as? Int else { throw BinUtilsError.wrongObjectType(format:c) }
    return UInt64(truncatingIfNeeded:i)
}

func intObject(_ o:Any, _ c:Character) throws -> Int {
    guard let i = o as? Int else { throw BinUtilsError.wrongObjectType(format:c) }
    return i
}

func doubleObject(_ o:Any, _ c:Character) throws -> Double {
    guard let d = o as? Double else { throw BinUtilsError.wrongObjectType(format:c) }
    return d
}

public func pack(_ format:String, _ objects:[Any], _ stringEncoding:String.Encoding=String.Encoding.windowsCP1252) throws -> Data {

    assert(CFByteOrderGetCurrent() == 1 /* CFByteOrderLittleEndian */, "\(#file) assumes little endian, but host is big endian")

    var objectsQueue = objects

    var mutableFormat = format

    var mutableData = Data()

    var isBigEndian = false

    guard !mutableFormat.isEmpty else { throw BinUtilsError.emptyFormat }

    let firstCharacter = mutableFormat.remove(at: mutableFormat.startIndex)

    switch(firstCharacter) {
    case "<", "=":
        isBigEndian = false
    case ">", "!":
        isBigEndian = true
    default:
        throw BinUtilsError.invalidByteOrder(character:firstCharacter)
    }

    var n = 0 // repeat counter

    while !mutableFormat.isEmpty {

        let c = mutableFormat.remove(at: mutableFormat.startIndex)

        if parseRepeatCountDigit(c, into:&n) { continue }

        var o : Any = 0

        if c == "s" {
            guard !objectsQueue.isEmpty else { throw BinUtilsError.missingObject(format:c) }
            o = objectsQueue.removeFirst()

            guard let s = o as? String else { throw BinUtilsError.wrongObjectType(format:c) }
            guard let stringData = s.data(using: stringEncoding) else {
                throw BinUtilsError.stringEncodingError(string:s, encoding:stringEncoding)
            }
            var bytes = stringData.bytes

            let expectedSize = max(1, n)

            // pad ...
            while bytes.count < expectedSize { bytes.append(0x00) }

            // ... or trunk
            if bytes.count > expectedSize { bytes = Array(bytes[0..<expectedSize]) }

            assert(bytes.count == expectedSize)

            // strings ('s') are raw byte sequences and are NOT affected by
            // the byte-order specifier, matching Python's struct module

            mutableData.append(bytes, count: bytes.count)

            n = 0
            continue
        }

        for _ in 0..<max(n,1) {

            var bytes : [UInt8] = []

            if c != "x" {
                guard !objectsQueue.isEmpty else { throw BinUtilsError.missingObject(format:c) }
                o = objectsQueue.removeFirst()
            }

            switch(c) {
            case "?":
                guard let b = o as? Bool else { throw BinUtilsError.wrongObjectType(format:c) }
                bytes = b ? [0x01] : [0x00]
            case "c":
                guard let ns = o as? NSString else { throw BinUtilsError.wrongObjectType(format:c) }
                let charAsString = ns.substring(to: 1)
                guard let data = charAsString.data(using: stringEncoding) else {
                    throw BinUtilsError.stringEncodingError(string:charAsString, encoding:stringEncoding)
                }
                bytes = data.bytes
            case "b":
                bytes = Int8(truncatingIfNeeded:try intObject(o, c)).data.bytes
            case "h":
                bytes = Int16(truncatingIfNeeded:try intObject(o, c)).data.bytes
            case "i", "l":
                bytes = Int32(truncatingIfNeeded:try intObject(o, c)).data.bytes
            case "q":
                bytes = Int64(truncatingIfNeeded:try intObject(o, c)).data.bytes
            case "Q":
                bytes = try uint64Value(o, c).data.bytes
            case "B":
                bytes = UInt8(truncatingIfNeeded:try intObject(o, c)).data.bytes
            case "H":
                bytes = UInt16(truncatingIfNeeded:try intObject(o, c)).data.bytes
            case "I", "L":
                bytes = UInt32(truncatingIfNeeded:try intObject(o, c)).data.bytes
            case "f":
                bytes = Float32(try doubleObject(o, c)).data.bytes
            case "d":
                bytes = Float64(try doubleObject(o, c)).data.bytes
            case "x":
                bytes = [0x00]
            default:
                throw BinUtilsError.unsupportedFormat(character:c)
            }

            if isBigEndian { bytes = bytes.reversed() }
            let data = Data(bytes)
            mutableData.append(data)
        }

        n = 0
    }

    return mutableData
}

public func unpack(_ format:String, _ data:Data, _ stringEncoding:String.Encoding=String.Encoding.windowsCP1252) throws -> [Unpackable] {

    assert(CFByteOrderGetCurrent() == 1 /* CFByteOrderLittleEndian */, "\(#file) assumes little endian, but host is big endian")

    let isBigEndian = isBigEndianFromMandatoryByteOrderFirstCharacter(format)

    if formatDoesMatchDataLength(format, data: data) == false {
        throw BinUtilsError.formatDoesMatchDataLength(format:format, dataSize:data.count)
    }

    var a : [Unpackable] = []

    var loc = 0

    let bytes = data.bytes

    var n = 0 // repeat counter

    var mutableFormat = format

    mutableFormat.remove(at: mutableFormat.startIndex) // consume byte-order specifier

    while !mutableFormat.isEmpty {

        let c = mutableFormat.remove(at: mutableFormat.startIndex)

        if parseRepeatCountDigit(c, into:&n) { continue }

        if c == "s" {
            let length = max(n,1)
            let sub = Array(bytes[loc..<loc+length])

            guard let s = NSString(bytes: sub, length: length, encoding: stringEncoding.rawValue) else {
                assertionFailure("-- not a string: \(sub)")
                return []
            }

            a.append(s)

            loc += length

            n = 0

            continue
        }

        for _ in 0..<max(n,1) {

            var o : Unpackable?

            switch(c) {

            case "c":
                let optionalString = NSString(bytes: [bytes[loc]], length: 1, encoding: stringEncoding.rawValue)
                loc += 1
                guard let s = optionalString else { assertionFailure(); return [] }
                o = s
            case "b":
                let r = readIntegerType(Int8.self, bytes:bytes, loc:&loc)
                o = Int(r)
            case "B":
                let r = readIntegerType(UInt8.self, bytes:bytes, loc:&loc)
                o = Int(r)
            case "?":
                let r = readIntegerType(Bool.self, bytes:bytes, loc:&loc)
                o = r ? true : false
            case "h":
                let r = readIntegerType(Int16.self, bytes:bytes, loc:&loc)
                o = Int(isBigEndian ? Int16(bigEndian: r) : r)
            case "H":
                let r = readIntegerType(UInt16.self, bytes:bytes, loc:&loc)
                o = Int(isBigEndian ? UInt16(bigEndian: r) : r)
            case "i":
                fallthrough
            case "l":
                let r = readIntegerType(Int32.self, bytes:bytes, loc:&loc)
                o = Int(isBigEndian ? Int32(bigEndian: r) : r)
            case "I":
                fallthrough
            case "L":
                let r = readIntegerType(UInt32.self, bytes:bytes, loc:&loc)
                o = Int(isBigEndian ? UInt32(bigEndian: r) : r)
            case "q":
                let r = readIntegerType(Int64.self, bytes:bytes, loc:&loc)
                o = Int(isBigEndian ? Int64(bigEndian: r) : r)
            case "Q":
                let r = readIntegerType(UInt64.self, bytes:bytes, loc:&loc)
                // returned as UInt (not Int) so the full UInt64 range is
                // representable without trapping for values > Int64.max
                o = UInt(isBigEndian ? UInt64(bigEndian: r) : r)
            case "f":
                let r = readFloatingPointType(Float32.self, bytes:bytes, loc:&loc, isBigEndian:isBigEndian)
                o = Double(r)
            case "d":
                let r = readFloatingPointType(Float64.self, bytes:bytes, loc:&loc, isBigEndian:isBigEndian)
                o = Double(r)
            case "x":
                loc += 1
            case " ":
                ()
            default:
                throw BinUtilsError.unsupportedFormat(character:c)
            }

            if let o = o { a.append(o) }
        }

        n = 0
    }

    return a
}
