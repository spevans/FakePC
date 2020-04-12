//
//  i8254.swift
//
//  Created by Simon Evans on 12/04/2020.
//
//  PIT 8254 Programmable Interval Timer.
//

import Dispatch
import HypervisorKit


final class PIT: ISAIOHardware {

    private let queue = DispatchQueue(label: "pit_timer")
    private let timer: DispatchSourceTimer
    private var timerActivated = false

    private let pic: PIC

    init(pic: PIC) {
        self.pic = pic

        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler {
            pic.send(irq: 0)
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
            print("Activating timer")
            timer.activate()
            timerActivated = true
        }
    }
}
