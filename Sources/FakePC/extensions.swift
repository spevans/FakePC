//
//  extensions.swift
//
//
//  Created by Simon Evans on 03/01/2020.
//


#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif


extension Bool {
    init(_ value: Int) {
        precondition(value == 0 || value == 1)
        self = value == 1 ? true : false
    }
}


extension Int {
    init(_ value: Bool) {
        self = value ? 1 : 0
    }
}


extension UnsafeMutableRawPointer {
    func unalignedStoreBytes<T>(of value: T, toByteOffset offset: Int, as type: T.Type) {
        var _value = value
        memcpy(self.advanced(by: offset), &_value, MemoryLayout<T>.size)
    }
}

extension UnsafeRawPointer {
    func unalignedLoad<T: FixedWidthInteger>(fromByteOffset offset: Int = 0, as type: T.Type) -> T {
        var value = T(0)
        memcpy(&value, self.advanced(by: offset), MemoryLayout<T>.size)
        return value
    }
}



extension UInt8 {
    init?(bcdValue: UInt8) {
        let lo = bcdValue & 0xf
        let hi = bcdValue >> 4
        guard lo <= 9, hi <= 9 else { return nil }
        self = (10 * hi) + lo
    }

    var bcdValue: UInt8? {
        guard self < 99 else { return nil }
        let hi = self / 10
        let lo = self % 10
        return (hi << 4) | lo
    }
}


func hexNum<T: BinaryInteger>(_ value: T, width: Int) -> String {
    let num = String(value, radix: 16)
    if num.count <= width {
        return String(repeating: "0", count: width - num.count) + num
    }
    return num
}
