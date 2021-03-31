//
//  Int1ARTC.swift
//  FakePC
//
//  Created by Simon Evans on 31/03/2021.
//  Copyright © 2021 Simon Evans. All rights reserved.
//
//  INT 1Ah BIOS Real time clock services.
//

import HypervisorKit

extension RTC {

    private enum BIOSFunction: UInt8 {
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


    func biosCall(function: UInt8, registers: VirtualMachine.VCPU.Registers, _ vm: VirtualMachine) {
        guard let rtcFunction = BIOSFunction(rawValue: function) else {
            logger.debug("RTC: Invalid function: \(String(function, radix: 16))")
            registers.rflags.carry = true
            return
        }

        switch rtcFunction {
            case .readSystemClockCounter: fallthrough
            case .setSystemClockCounter:
                fatalError("Should be handled by BIOS")

            case .readRealTimeClockTime:
                registers.ch = toBCD(staticRam.rtcHour)
                registers.cl = toBCD(staticRam.rtcMinute)
                registers.dh = toBCD(staticRam.rtcSecond)
                registers.dl = staticRam.daylightSavings ? 1 : 0
                registers.rflags.carry = false

            case .setRealTimeClockTime:
                staticRam.rtcHour = fromBCD(registers.ch)
                staticRam.rtcMinute = fromBCD(registers.cl)
                staticRam.rtcSecond = fromBCD(registers.dh)
                staticRam.daylightSavings = (registers.dl == 0) ? false : true
                registers.rflags.carry = false

            case .readRealTimeClockDate:
                registers.ch = toBCD(staticRam.rtcCentury)
                registers.cl = toBCD(staticRam.rtcYear)
                registers.dh = toBCD(staticRam.rtcMonth)
                registers.dl = toBCD(staticRam.rtcDayOfMonth)
                registers.rflags.carry = false

            case .setRealTimeClockDate:
                staticRam.rtcCentury = registers.ch
                staticRam.rtcYear = fromBCD(registers.cl)
                staticRam.rtcMonth = fromBCD(registers.dh)
                staticRam.rtcDayOfMonth = fromBCD(registers.dl)
                registers.rflags.carry = false

            case .setRealTimeClockAlarm:
                if staticRam.registerA.timeUpdateInProgress || staticRam.registerB.alarmInterruptEnabled {
                    registers.rflags.carry = true
                } else {
                    staticRam.alarmHour = fromBCD(registers.ch)
                    staticRam.alarmMinute = fromBCD(registers.cl)
                    staticRam.alarmSecond = fromBCD(registers.dh)
                    registers.rflags.carry = false
                }

            case .resetRealTimeClockAlarm:
                staticRam.registerB.alarmInterruptEnabled = false
                registers.rflags.carry = false

            case .setRealTimeClockActivatePowerOnMode: fallthrough
            case .readRealTimeClockAlarm: fallthrough

            // Days since Jan 1 1980 in CX
            case .readSystemDayCounter: fallthrough
            case .setSystemDayCounter:
                fatalError("RTC: Unimplmented function: \(function)")
        }
    }
}
