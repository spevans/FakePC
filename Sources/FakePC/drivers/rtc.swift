//
//  rtc.swift
//  FakePC
//
//  Created by Simon Evans on 16/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Emulation of CMOS RTC and BIOS INT 1A calls.
//

import Foundation
import HypervisorKit


class RTC: ISAIOHardware {

    private let pic: PIC


    init(pic: PIC) {
        self.pic = pic
    }


    // INT 0x1A
    func biosCall(_ ax: UInt16, _ vm: VirtualMachine) {
        let function = UInt8(ax >> 8)
        let vcpu = vm.vcpus[0]

        enum RTCFunctions: UInt8 {
        case readSystemClockCounter = 0
        case setSystemClockCounter = 1
        case readRealTimeClockTime = 2
        case setRealTimeClockTime = 3
        case readRealTimeClockDate = 4
        case setRealTimeClockDate = 5
        case setRealTimeClockAlarm = 6
        case resetRealTimeClockAlarm = 7
        case setRealTimeClockActivatePowerOnMode = 8
        case readRealTimeClockAlarm = 9
        case readSystemDayCounter = 0xA
        case setSystemDayCounter = 0xB
        }

        guard let rtcFunction = RTCFunctions(rawValue: function) else {
            print("RTC: Invalid function: \(String(function, radix: 16))")
            vcpu.registers.rflags.carry = true
            return
        }


        func toBCD(_ value: UInt8) -> UInt8 {
            return (value / 10) << 4 | (value % 10)
        }

        let now = Date()
        let calendar = Calendar.current
        let tz = calendar.timeZone

        switch rtcFunction {
            case .readSystemClockCounter:
            let clockTicks = clock()
#if os(Linux)
            // clock() returns -1 for errors on Linux
            guard clockTicks >= 0 else {
                vcpu.registers.rflags.carry = true
                return
            }
#endif

            let clocksPerSec = UInt(CLOCKS_PER_SEC)
            let count = (18 * UInt(clockTicks)) / clocksPerSec
            let cxdx = UInt32(truncatingIfNeeded: count)
            vcpu.registers.al = 0
            vcpu.registers.cx = UInt16(cxdx >> 16)
            vcpu.registers.dx = UInt16(truncatingIfNeeded: cxdx)
            vcpu.registers.rflags.carry = false
            return

        case .readRealTimeClockTime:
            let components = calendar.dateComponents([.hour, .minute, .second], from: now)
            guard let hour = components.hour, let minute = components.minute, let second = components.second else {
                vcpu.registers.rflags.carry = true
                return
            }

            vcpu.registers.ch = toBCD(UInt8(hour))
            vcpu.registers.cl = toBCD(UInt8(minute))
            vcpu.registers.dh = toBCD(UInt8(second))
            vcpu.registers.dl = tz.isDaylightSavingTime(for: now) ? 1 : 0
            vcpu.registers.rflags.carry = false

        case .readRealTimeClockDate:
            let components = calendar.dateComponents([.year, .month, .day], from: now)
            guard let year = components.year, let month = components.month, let day = components.day else {
                vcpu.registers.rflags.carry = true
                return
            }

            vcpu.registers.ch = toBCD(UInt8(year / 100))
            vcpu.registers.cl = toBCD(UInt8(year % 100))
            vcpu.registers.dh = toBCD(UInt8(month))
            vcpu.registers.dl = toBCD(UInt8(day))
            vcpu.registers.rflags.carry = false

        default:
            print("RTC: Invalid function: \(function)")
            vcpu.registers.rflags.carry = true
            return
        }
    }
}
