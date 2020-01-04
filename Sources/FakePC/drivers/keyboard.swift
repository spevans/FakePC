//
//  keyboard.swift
//  
//
//  Created by Simon Evans on 01/01/2020.
//

import Foundation
import HypervisorKit



// INT 0x16




func keyboard(_ ax: UInt16, _ vm: VirtualMachine) {
    let function = UInt8(ax >> 8)
//    print("KEYBOARD: function = 0x\(String(function, radix: 16)) not implemented")
    var bda = BDA()
    bda.timerCount += 100
//    print("bda.timerCount:", bda.timerCount)
}
