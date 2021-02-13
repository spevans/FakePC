//
//  rtc.swift
//  FakePC
//
//  Created by Simon Evans on 16/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Emulation of CMOS RTC and BIOS INT 1Ah calls.
//

import Foundation
import HypervisorKit


// TODO: Add timer control so set the clock at different rates.
// TODO: Add interrupt triggers for the alarm and periodic timer.
// TODO: Add more RegisterA - RegisterD flags and make use of them.
// TODO: Move BCD functions to a UInt8 extension.
// TODO: Make use of the daylight savings flags, enable automatic update when necessary.

final class RTC: ISAIOHardware {

    struct StaticRam {

        struct RegisterA {
            var value = BitArray8(0)

            var rawValue: UInt8 { value.rawValue }
            var timeUpdateInProgress: Bool { get { Bool(value[7]) } set { value[7] = Int(newValue) } }

            init(_ rawValue: UInt8) {
                value = BitArray8(rawValue)
            }
        }

        struct RegisterB {
            var value = BitArray8(0)
            var rawValue: UInt8 { value.rawValue }

            var automaticDaylightSavingsEnable: Bool { Bool(value[0]) }

            var hourMode24: Bool { Bool(value[1]) }
            var hourMode12: Bool { !hourMode24 }

            var dataModeBinary: Bool { get { Bool(value[2]) }  set { value[2] = Int(newValue) } }
            var dataModeBCD:    Bool { get { !dataModeBinary } set { dataModeBinary = !newValue } }

            var squareWaveOutputEnabled:        Bool { get { Bool(value[3]) } set { value[3] = Int(newValue) } }
            var updateEndedInterruptEnabled:    Bool { get { Bool(value[4]) } set { value[4] = Int(newValue) } }
            var alarmInterruptEnabled:          Bool { get { Bool(value[5]) } set { value[5] = Int(newValue) } }
            var periodicInterruptEnabled:       Bool { get { Bool(value[6]) } set { value[6] = Int(newValue) } }
            var enableClockSetting:             Bool { get { Bool(value[7]) } set { value[7] = Int(newValue) } }

            init(_ rawValue: UInt8) {
                value = BitArray8(rawValue)
            }
        }

        struct RegisterC {
            var value = BitArray8(0)
            var rawValue: UInt8 { value.rawValue }

            init(_ rawValue: UInt8) {
                value = BitArray8(rawValue)
            }
        }

        struct RegisterD {
            var value = BitArray8(0)
            var rawValue: UInt8 { value.rawValue }

            init(_ rawValue: UInt8) {
                value = BitArray8(rawValue)
            }
        }

        private var storage = Array<UInt8>(repeating: 0, count: 64)
        private let calendar: Calendar
        private let timeZone: TimeZone
        fileprivate var daylightSavings: Bool

        subscript(index: Int) -> UInt8 {
            get { storage[index & 0x3f] }
            set { storage[index & 0x3f] = newValue }
        }

        // These values ( are stored as normal 8but values and NOT BCD.
        // Appropiate conversion is done when reading / writing port 0x71
        var rtcSecond:      UInt8 { get { storage[0] } set { storage[0] = newValue } }
        var alarmSecond:    UInt8 { get { storage[1] } set { storage[1] = newValue } }
        var rtcMinute:      UInt8 { get { storage[2] } set { storage[2] = newValue } }
        var alarmMinute:    UInt8 { get { storage[3] } set { storage[3] = newValue } }
        var rtcHour:        UInt8 { get { storage[4] } set { storage[4] = newValue } }
        var alarmHour:      UInt8 { get { storage[5] } set { storage[5] = newValue } }
        var rtcDayOfWeek:   UInt8 { get { storage[6] } set { storage[6] = newValue } }
        var rtcDayOfMonth:  UInt8 { get { storage[7] } set { storage[7] = newValue } }
        var rtcMonth:       UInt8 { get { storage[8] } set { storage[8] = newValue } }
        var rtcYear:        UInt8 { get { storage[9] } set { storage[9] = newValue } }
        var registerA:      RegisterA { get { RegisterA(storage[0xA]) }  set { storage[0xA] = newValue.rawValue } }
        var registerB:      RegisterB { get { RegisterB(storage[0xB]) }  set { storage[0xB] = newValue.rawValue } }
        var registerC:      RegisterC { get { RegisterC(storage[0xC]) }  set { storage[0xC] = newValue.rawValue } }
        var registerD:      RegisterD { get { RegisterD(storage[0xD]) }  set { storage[0xD] = newValue.rawValue } }
        var rtcCentury:     UInt8 { get { storage[0x32] } set { storage[0x32] = newValue } }


        mutating func setDateFrom(components: DateComponents) {
            if let year = components.year, let month = components.month, let day = components.day, let weekday = components.weekday,
                let hour = components.hour, let minute = components.minute, let second = components.second {
                rtcCentury = UInt8(year / 100)
                rtcYear = UInt8(year % 100)
                rtcMonth = UInt8(month)
                rtcDayOfMonth = UInt8(day)
                rtcDayOfWeek = UInt8(weekday)
                rtcHour = UInt8(hour)
                rtcMinute = UInt8(minute)
                rtcSecond = UInt8(second)
            }
            logger.debug("Current Date set to: \(currentDate as Any)")
        }


        init() {
            calendar = Calendar.current
            timeZone = calendar.timeZone
            let now = Date()
            daylightSavings = timeZone.isDaylightSavingTime(for: now)

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: now)
            setDateFrom(components: components)
        }


        mutating func updateRTC() {
            registerA.timeUpdateInProgress = true
            defer { registerA.timeUpdateInProgress = false }

            rtcSecond += 1
            if rtcSecond < 60 { return }

            rtcSecond = 0
            rtcMinute += 1
            if rtcMinute < 60 { return }

            rtcMinute = 0
            rtcHour += 1
            if rtcHour < 23 { return }

            let year = Int(rtcCentury) * 100 + Int(rtcYear)
            let components = DateComponents(calendar: calendar, timeZone: timeZone,
                                            year: year, month: Int(rtcMonth), day: Int(rtcDayOfMonth),
                                            hour: Int(rtcHour), minute: Int(rtcMinute), second: Int(rtcSecond))
            if let currentDate = components.date,
                let newDate = calendar.date(byAdding: .hour, value: 1, to: currentDate) {
                let components = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute, .second], from: newDate)
                setDateFrom(components: components)
            }
        }


        func checkAlarm() {
            guard registerB.alarmInterruptEnabled else { return }
            // Alarm values between 0xC0 and 0xFF are treated as 'dont care' and act as it that component matched.
            if alarmSecond < 0xC0 && alarmSecond != rtcSecond { return }
            if alarmMinute < 0xC0 && alarmMinute != rtcMinute { return }
            if alarmHour < 0xC0 && alarmHour != rtcHour { return }
            logger.debug("RTC Alarm")
        }


        var currentDate: Date? {
            let year = Int(rtcCentury) * 100 + Int(rtcYear)
            let components = DateComponents(calendar: calendar, timeZone: timeZone,
                                            year: year, month: Int(rtcMonth), day: Int(rtcDayOfMonth),
                                            hour: Int(rtcHour), minute: Int(rtcMinute), second: Int(rtcSecond))
            return components.date
        }
    }


    private var enableNMI = true
    private var cmosRegisterSelected = 0
    private var staticRam = StaticRam()
    private let queue = DispatchQueue(label: "cmos_timer")
    private let timer: DispatchSourceTimer


    init() {
        staticRam[0x0E] = 0    // Diagnostic Status Byte, all OK
        staticRam[0x0F] = 0xff // Shutdown byte, FF = Perform power on reset
        staticRam[0x10] = 0x55 // Two floppy drives both 3.5" 2.88MB

        timer = DispatchSource.makeTimerSource(queue: queue)

        timer.setEventHandler {
            self.staticRam.updateRTC()
            self.staticRam.checkAlarm()
        }
        // Setup a 1second timer to update the RTC
        timer.schedule(deadline: .now(), repeating: .milliseconds(1000))
    }


    // Used to set the seconds counter incremented by the timer on IRQ0
    func secondsSinceMidnight() -> UInt32 {
        let seconds = (UInt32(staticRam.rtcHour) * 3600) + (UInt32(staticRam.rtcMinute) * 60) + UInt32(staticRam.rtcSecond)
        return seconds
    }


    private func toBCD(_ value: UInt8) -> UInt8 {
        return ((value / 10) << 4 | (value % 10))
    }

    private func toBCDIfNeeded(_ value: UInt8, isHour: Bool = false) -> UInt8 {
        let isPM: UInt8 = isHour && staticRam.registerB.hourMode12 && (value > 12) ? 0x80 : 0
        if staticRam.registerB.dataModeBCD {
            return toBCD(value) | isPM
        } else {
            return value | isPM
        }
    }


    private func fromBCD(_ value: UInt8) -> UInt8 {
        return UInt8(10 * (value >> 4)) + UInt8(value & 0xff)
    }

    private func fromBCDIfNeeded(_ value: UInt8, isHour: Bool = false) -> UInt8 {
        let registerB = staticRam.registerB
        let isPM = isHour && registerB.hourMode12 && (value & 0x80 == 0x80)
        if registerB.dataModeBCD {
            let result = fromBCD(value)
            return isPM ? result + 12 : result
        } else {
            return value
        }
    }

    private func fromBCDIfNeeded(_ value: Int, isHour: Bool = false) -> UInt8 {
        return fromBCDIfNeeded(UInt8(value), isHour: isHour)
    }


    func ioOut(port: IOPort, operation: VMExit.DataWrite) throws {
        guard case .byte(let byte) = operation else { return }
        switch port {
            case 0x70:
                cmosRegisterSelected = Int(byte) & 0x3f
                enableNMI = (byte & 0x80) == 0

            case 0x71:
                switch cmosRegisterSelected {
                    case 0...3, 6...9: staticRam[cmosRegisterSelected] = fromBCDIfNeeded(byte)
                    case 4...5: staticRam[cmosRegisterSelected] = fromBCDIfNeeded(byte, isHour: true)
                    case 0x32:  staticRam.rtcCentury = fromBCD(byte)
                    default: staticRam[cmosRegisterSelected] = byte
            }
            default: fatalError("RTC: Only expected OUT on 0x70/0x71, not 0x\(String(port, radix: 16))")
        }
    }


    func ioIn(port: IOPort, operation: VMExit.DataRead) -> VMExit.DataWrite {
        let result: VMExit.DataWrite
        switch port {
            case 0x70:
                let value = UInt8((cmosRegisterSelected & 0x3f)  | (enableNMI ? 0 : 0x80))
                result = .byte(value)

            case 0x71:
                switch cmosRegisterSelected {
                    case 0...3, 6...9: result = .byte(toBCDIfNeeded(staticRam[cmosRegisterSelected]))
                    case 4...5: result = .byte(toBCDIfNeeded(staticRam[cmosRegisterSelected], isHour: true))
                    case 0x32:  result = .byte(toBCD(staticRam.rtcCentury))
                    default: result = .byte(staticRam[cmosRegisterSelected])
            }

            default: fatalError("RTC: Only expected IN on 0x70/0x71, not 0x\(String(port, radix: 16))")
        }
        return result
    }
}


// INT 1Ah BIOS interface.
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


    func biosCall(_ ax: UInt16, _ vm: VirtualMachine) {
        let function = UInt8(ax >> 8)
        let vcpu = vm.vcpus[0]

        guard let rtcFunction = BIOSFunction(rawValue: function) else {
            logger.debug("RTC: Invalid function: \(String(function, radix: 16))")
            vcpu.registers.rflags.carry = true
            return
        }

        switch rtcFunction {
            case .readSystemClockCounter: fallthrough
            case .setSystemClockCounter:
                fatalError("Should be handled by BIOS")

            case .readRealTimeClockTime:
                vcpu.registers.ch = toBCD(staticRam.rtcHour)
                vcpu.registers.cl = toBCD(staticRam.rtcMinute)
                vcpu.registers.dh = toBCD(staticRam.rtcSecond)
                vcpu.registers.dl = staticRam.daylightSavings ? 1 : 0
                vcpu.registers.rflags.carry = false

            case .setRealTimeClockTime:
                staticRam.rtcHour = fromBCD(vcpu.registers.ch)
                staticRam.rtcMinute = fromBCD(vcpu.registers.cl)
                staticRam.rtcSecond = fromBCD(vcpu.registers.dh)
                staticRam.daylightSavings = (vcpu.registers.dl == 0) ? false : true
                vcpu.registers.rflags.carry = false

            case .readRealTimeClockDate:
                vcpu.registers.ch = toBCD(staticRam.rtcCentury)
                vcpu.registers.cl = toBCD(staticRam.rtcYear)
                vcpu.registers.dh = toBCD(staticRam.rtcMonth)
                vcpu.registers.dl = toBCD(staticRam.rtcDayOfMonth)
                vcpu.registers.rflags.carry = false

            case .setRealTimeClockDate:
                staticRam.rtcCentury = vcpu.registers.ch
                staticRam.rtcYear = fromBCD(vcpu.registers.cl)
                staticRam.rtcMonth = fromBCD(vcpu.registers.dh)
                staticRam.rtcDayOfMonth = fromBCD(vcpu.registers.dl)
                vcpu.registers.rflags.carry = false

            case .setRealTimeClockAlarm:
                if staticRam.registerA.timeUpdateInProgress || staticRam.registerB.alarmInterruptEnabled {
                    vcpu.registers.rflags.carry = true
                } else {
                    staticRam.alarmHour = fromBCD(vcpu.registers.ch)
                    staticRam.alarmMinute = fromBCD(vcpu.registers.cl)
                    staticRam.alarmSecond = fromBCD(vcpu.registers.dh)
                    vcpu.registers.rflags.carry = false
                }

            case .resetRealTimeClockAlarm:
                staticRam.registerB.alarmInterruptEnabled = false
                vcpu.registers.rflags.carry = false

            case .setRealTimeClockActivatePowerOnMode: fallthrough
            case .readRealTimeClockAlarm: fallthrough

            // Days since Jan 1 1980 in CX
            case .readSystemDayCounter: fallthrough
            case .setSystemDayCounter:
                fatalError("RTC: Unimplmented function: \(function)")
        }
    }
}
