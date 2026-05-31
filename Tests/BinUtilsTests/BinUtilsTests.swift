//
//  BinUtilsTests.swift
//  BinUtilsTests
//
//  Created by Nicolas Seriot on 14/03/16.
//  Copyright © 2016 Nicolas Seriot. All rights reserved.
//

import Foundation
import XCTest
@testable import BinUtils

class BinUtilsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testUnhexlify() {
        let s = String(data: unhexlify("48656C6C6F")!, encoding: .utf8)
        XCTAssertEqual(s, "Hello")
    }

    func testHexlifyUnhexlify() {
        let s1 = "ABcdEF"

        let s2 = hexlify(unhexlify(s1)!)

        XCTAssertEqual(s1.lowercased(), s2)
    }

    func testUnhexlifyOddLengthReturnsNil() {
        XCTAssertNil(unhexlify("ABC"))
    }

    func testPackStringBigEndian() {
        // strings are raw bytes and must not be reversed by the byte order
        let data = pack(">2s", ["as"])
        XCTAssertEqual(data, unhexlify("6173"))
    }

    func testPackUnpackStringBigEndian() {
        let data = pack(">3s", ["abc"])
        let a = try! unpack(">3s", data)
        XCTAssertEqual(a[0] as? NSString, "abc")
    }

    func testUnpackWithFile() {
        let path = "/bin/ls"
        if let f = FileHandle(forReadingAtPath: path) {
            let a = try! unpack("<2H", f.readData(ofLength: 4))
            f.closeFile()

            XCTAssertEqual(a[0] as? Int, 65226) // CAFE
            XCTAssertEqual(a[1] as? Int, 48826) // BABE
        } else {
            XCTFail("cannot open \("/bin/ls") for reading")
        }
    }

    func testUnpack1() {
        let a = try! unpack(">hBsf", unhexlify("050001413fc00000")!)

        XCTAssertEqual(a[0] as? Int, 1280)
        XCTAssertEqual(a[1] as? Int, 1)
        XCTAssertEqual(a[2] as? NSString, "A")
        XCTAssertEqual(a[3] as? Double, 1.5)
    }

    func testUnpack2() {
        let a = try! unpack("<I 2s f", unhexlify("010000006162cdcc2c40")!)

        XCTAssertEqual(a[0] as? Int, 1)
        XCTAssertEqual(a[1] as? NSString, "ab")
        XCTAssertEqual(a[2] as? Double, 2.700000047683716)
    }

    func testUnpack3() {
        let a = try! unpack("<2sss", unhexlify("41414141")!)

        XCTAssertEqual(a[0] as? NSString, "AA")
        XCTAssertEqual(a[1] as? NSString, "A")
        XCTAssertEqual(a[2] as? NSString, "A")
    }

    func testUnpackNothing() {
        let a = try! unpack("<", Data())
        assert(a.count == 0)
    }

    func testFormatSizes() {

        XCTAssertEqual(0, numberOfBytesInFormat(""))
        XCTAssertEqual(1, numberOfBytesInFormat(">x"))
        XCTAssertEqual(2, numberOfBytesInFormat(">h"))
        XCTAssertEqual(4, numberOfBytesInFormat(">I"))
        XCTAssertEqual(4_000, numberOfBytesInFormat(">1000I"))
        XCTAssertEqual(4_000_000, numberOfBytesInFormat(">1000000I"))
        XCTAssertEqual(4_000_000_000, numberOfBytesInFormat(">1000000000I"))
        XCTAssertEqual(5, numberOfBytesInFormat(">5s"))
        XCTAssertEqual(6, numberOfBytesInFormat(">5sb"))
        XCTAssertEqual(8, numberOfBytesInFormat(">hBsf"))
    }

    func testPackLittleEndian() {
        let data = pack("<Ih", [1, 2])
        XCTAssertEqual(data, unhexlify("01000000 0200"))
    }

    func testPackBigEndian() {
        let data = pack(">Ih?", [1, 2, true])
        XCTAssertEqual(data, unhexlify("00000001 0002 01"))
    }

    func testPackWithPadding() {
        let data = pack("<xh", [123])
        XCTAssertEqual(data, unhexlify("007b00"))
    }

    func testPackWithPaddingRepeat() {
        let data = pack("<2xh", [1])
        XCTAssertEqual(data, unhexlify("00000100"))
    }

    func testPackWithRepeats() {
        let data = pack("<h2I", [0, 1, 2])
        XCTAssertEqual(data, unhexlify("0000 01000000 02000000"))
    }

    func testPackWithRepeatsPlusCharacter() {
        let data = pack("<h2Ic", [0, 1, 2, "x"])
        XCTAssertEqual(data, unhexlify("0000 01000000 02000000 78"))
    }

    func testPackString() {
        let data = pack("<2s", ["as"])
        XCTAssertEqual(data, unhexlify("6173"))
    }

    func testPackString2() {
        let data = pack("<2s2s", ["as", "df"])
        XCTAssertEqual(data, unhexlify("6173 6466"))
    }

    func testPack() {
        let data = pack("<h2I3sf", [1, 2, 3, "asd", 0.5])
        XCTAssertEqual(data, unhexlify("0100 02000000 03000000 617364 0000003f"))
    }

    func testPackUnpackNetworkOrder() {
        // http://effbot.org/librarybook/struct.htm
        let data = pack("!ihb", [1, 2, 3])
        let a = try! unpack("!ihb", data)
        XCTAssertEqual(a[0] as? Int, 1)
        XCTAssertEqual(a[1] as? Int, 2)
        XCTAssertEqual(a[2] as? Int, 3)
    }
}

extension BinUtilsTests {
    static var allTests: [
        ( String, (BinUtilsTests) -> () throws -> Void )
        ]
    {
        return [
            ("testUnhexlify", testUnhexlify),
            ("testUnhexlifyOddLengthReturnsNil", testUnhexlifyOddLengthReturnsNil),
            ("testHexlifyUnhexlify", testHexlifyUnhexlify),
            ("testPackStringBigEndian", testPackStringBigEndian),
            ("testPackUnpackStringBigEndian", testPackUnpackStringBigEndian),
            ("testUnpack1", testUnpack1),
            ("testUnpack2", testUnpack2),
            ("testUnpack3", testUnpack3),
            ("testUnpackNothing", testUnpackNothing),
            ("testFormatSizes", testFormatSizes),
            ("testPackLittleEndian", testPackLittleEndian),
            ("testPackBigEndian", testPackBigEndian),
            ("testPackWithPadding", testPackWithPadding),
            ("testPackWithPaddingRepeat", testPackWithPaddingRepeat),
            ("testPackWithRepeats", testPackWithRepeats),
            ("testPackWithRepeatsPlusCharacter", testPackWithRepeatsPlusCharacter),
            ("testPackString", testPackString),
            ("testPack", testPack),
            ("testPackUnpackNetworkOrder", testPackUnpackNetworkOrder),
        ]
    }
}
