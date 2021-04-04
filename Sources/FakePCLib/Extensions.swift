//
//  Extensions.swift
//  FakePC
//
//  Created by Simon Evans on 04/04/2021.
//  Copyright © 2021 Simon Evans. All rights reserved.
//

import Foundation


internal extension Data {

    func readLSB16() -> UInt16 {
        let index = self.startIndex
        return UInt16(self[index + 0]) | UInt16(self[index + 1]) << 8
    }

    func readLSB32() -> UInt32 {
        let index = self.startIndex
        return UInt32(self[index + 0]) | UInt32(self[index + 1]) << 8 | UInt32(self[index + 2]) << 16 | UInt32(self[index + 3]) << 24
    }
}
