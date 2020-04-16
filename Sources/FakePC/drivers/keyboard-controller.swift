//
//  keyboard.swift
//  FakePC
//
//
//  Created by Simon Evans on 17/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//

import Foundation
import HypervisorKit


final class KeyboardController: ISAIOHardware {

    private let pic: PIC


    init(pic: PIC) {
        self.pic = pic
    }


    // INT 0x16
    func biosCall(_ ax: UInt16, _ vm: VirtualMachine) {
        //    let function = UInt8(ax >> 8)
        let bda = BDA()
        if bda.timerCount > 0 {
            //        print("keyboard, timerCount:", bda.timerCount)
        }
    }
}
