//
//  i8254.swift
//  FakePC
//
//  Created by Simon Evans on 12/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  PIT 8254 Programmable Interval Timer.
//

import Dispatch
import HypervisorKit


final class PIT: ISAIOHardware {

    private let queue = DispatchQueue(label: "pit_timer")
    private let timer: DispatchSourceTimer
    private var timerActivated = false


    init() {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler {
            ISA.send(irq: 0)
        }
        // Setup the default 18.2 ticks/second timer, dont wait for programming
        timer.schedule(deadline: .now(), repeating: .milliseconds(55))
    }


    func ioOut(port: IOPort, operation: VMExit.DataWrite) throws {
    }


    func ioIn(port: IOPort, operation: VMExit.DataRead) -> VMExit.DataWrite {
        return VMExit.DataWrite(bitWidth: operation.bitWidth, value: 0)!
    }


    func process() {
        if !timerActivated {
            debugLog("i8254: Activating timer")
            timer.activate()
            timerActivated = true
        }
    }
}
