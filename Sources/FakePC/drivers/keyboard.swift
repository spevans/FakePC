//
//  keyboard.swift
//
//
//  Created by Simon Evans on 01/01/2020.
//

import Foundation
import HypervisorKit

// INT 0x16

func keyboard(_ ax: UInt16, _ vm: VirtualMachine) throws {
    //    let function = UInt8(ax >> 8)
    let bda = BDA()
    if bda.timerCount > 0 {
//        print("keyboard, timerCount:", bda.timerCount)
    }
}
