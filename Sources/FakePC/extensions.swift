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

extension UnsafeMutableRawPointer {
    func unalignedStoreBytes<T>(of value: T, toByteOffset offset: Int, as type: T.Type) {
        var _value = value
        memcpy(self.advanced(by: offset), &_value, MemoryLayout<T>.size)
    }
}
