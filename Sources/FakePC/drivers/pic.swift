// pic.swift
// Created 02/01/2020
//
// PIC 8259 emulattion and IRQ injection

import HypervisorKit

private extension UInt8 {
    var lowestBitSet: Int? {
        guard self != 0 else { return nil }
        return self.trailingZeroBitCount
    }

    mutating func clearLowestBitSet() {
        if let bit = lowestBitSet {
            self &= ~UInt8(1 << bit)
        }
    }
}


final class PIC {

    enum InitSequence {
    case waitingForICW1
    case startInitialisation
    case waitingForICW2
    case waitingForICW3
    case waitingForICW4
    case ready
    }

    private var state = InitSequence.waitingForICW1

    struct ICW1 {
        private let value: BitArray8

        init(_ value: UInt8) {
            self.value = BitArray8(value)
        }

        init?(value: UInt8) {
            let bits = BitArray8(value)
            guard bits[4] == 1 else {
                return nil   // Not a valid ICW1 command byte
            }
            self.value = bits
        }

        // Ignore 8080/85 mode specific bits
        var isIcw4Needed: Bool { value[0] == 1 }
        var isSingle: Bool { value[1] == 1}
        var isCascade: Bool { !isSingle }
        var isLevelTriggered: Bool { value[3] == 1 }
        var isValidICW1: Bool { value[4] == 1}
    }

    struct ICW2 {
        let value: UInt8
                
        // Ignore 8080/85 mode specific bits
        var irqBase: UInt8 { value & 0xf8 }
    }


    struct ICW3 {
        let value: UInt8
    }


    struct ICW4 {
        private let value: BitArray8

        init(value: UInt8) {
            self.value = BitArray8(value)
        }

        var mode8086: Bool { value[0] == 1 }
        var mode8080: Bool { !mode8086 }

        var autoEOI: Bool { value[1] == 1 }
        var normalEOI: Bool { !autoEOI }

        var nonBufferedMode: Bool { value[3] == 0 }
        var bufferedModeMaster: Bool { value[2...3] == 3 }

        var specialFullyNestedMode: Bool { value[4] == 1 }        
    }
    

    struct OCW1 {
        let value: UInt8
    }

    struct OCW2 {
        enum Command: UInt8 {
        case rotateInAutoEOIModeClear = 0
        case nonSpecificEOI = 1
        case noOperation = 2
        case specificEOI = 3
        case rotateInAutoEOIModeSet = 4
        case rotateOnNonSpecificEOI = 5
        case setPriorityCommand = 6
        case rotateOnSpecificEOI = 7
        }

        private let value: BitArray8

        init(_ value: UInt8) {
            self.value = BitArray8(value)
        }

        init?(value: UInt8) {
            let bits = BitArray8(value)
            guard bits[3...4] == 0 else {
                return nil   // Not a valid OCW2 command byte
            }
            self.value = bits
        }

        var isValid: Bool { value[3...4] == 0 }
        var irLevel: Int { Int(value[0...2]) }
        var command: Command { Command(rawValue: value.rawValue >> 5) ?? .noOperation }
    }

    struct OCW3 {
        private let value: BitArray8

        init(_ value: UInt8) {
            self.value = BitArray8(value)
        }

        init?(value: UInt8) {
            let bits = BitArray8(value)
            guard bits[3...4] == 1 && bits[7] == 0 else {
                return nil  // Not a valid OCW3 command byte
            }
            self.value = bits
        }

        var isValid: Bool { value[3...4] == 1 && value[7] == 0 }
        var readIRR: Bool { value[0...1] == 2 }
        var readISR: Bool { value[0...1] == 3 }
        var pollCommand: Bool { value[2] == 1 }
        var resetSpecialMask: Bool { value[5...6] == 2 }
        var setSpecialMask: Bool { value[5...6] == 3 }
    }

    
    var interruptRequestRegister: UInt8 = 0
    var inServiceRegister: UInt8 = 0
    var interruptMaskRegister: UInt8 = 0
    var vectorAddressBase: UInt8 = 0

    var icw1 = ICW1(0)
    var icw2 = ICW2(value: 0)
    var icw3 = ICW3(value: 0)
    var icw4 = ICW4(value: 0)
    var ocw1 = OCW1(value: 0)
    var ocw2 = OCW2(0)
    var ocw3 = OCW3(0)

    // Process bytes sent to PIC (using OUT instruction). a0 is true if
    // IO port is 0x21 or 0xA1, false if port is 0x20, 0xA0
    func writeByte(_ byte: UInt8, a0: Bool) {

        print("PIC write: a0: \(a0) byte: \(String(byte, radix: 16)), state: \(state)")
        

        switch state {

        case .waitingForICW1:
            // IF an ICW1 is seen, start initialisation
            if a0 == false, let icw1 = ICW1(value: byte) {
                self.icw1 = icw1
                state = .startInitialisation
            }
            
        case .startInitialisation:
            // Start initalisation loop
            interruptMaskRegister = 0
            ocw3 = OCW3(2) // Set IRR read
            if icw1.isIcw4Needed == false {
                icw4 = ICW4(value: 0)
            }
            state = .waitingForICW2

        case .waitingForICW2:
            if a0 {
                let icw2 = ICW2(value: byte)
                vectorAddressBase = icw2.irqBase
                if icw1.isCascade {
                    state = .waitingForICW3
                } else if icw1.isIcw4Needed {
                    state = .waitingForICW4
                } else {
                    state = .ready
                }
            }
            
        case .waitingForICW3:
            if a0 {
                self.icw3 = ICW3(value: byte)
                if icw1.isIcw4Needed {
                    state = .waitingForICW4
                } else {
                    state = .ready
                }
            }

        case .waitingForICW4:
            if a0 {
                self.icw4 = ICW4(value: byte)
                state = .ready
            }

        case .ready:
            // Look for Operation Control Words
            if a0 { // OCW1
                self.ocw1 = OCW1(value: byte)
                self.interruptMaskRegister = byte
            } else {
                if let ocw2 = OCW2(value: byte) {
                    self.ocw2 = ocw2

                    switch ocw2.command {
                    case .nonSpecificEOI:
                        // Clear current in service interrupt, set next one
                        inServiceRegister.clearLowestBitSet()
                        if let nextIrq = (interruptRequestRegister & ~interruptMaskRegister).lowestBitSet {
                            interruptRequestRegister.clearLowestBitSet()
                            print("PIC: Signalling next IRQ: \(nextIrq)")
                        }
                        
                    case .rotateInAutoEOIModeClear: fallthrough
                    case .specificEOI: fallthrough
                    case .rotateInAutoEOIModeSet: fallthrough
                    case .rotateOnNonSpecificEOI: fallthrough
                    case .setPriorityCommand: fallthrough
                    case .rotateOnSpecificEOI:
                        print("PIC: Ignoring command: \(ocw2.command)")

                    case .noOperation: break
                    }

                    
                } else if let ocw3 = OCW3(value: byte) {
                    self.ocw3 = ocw3
                }
            }
        }
        print("PIC: write finished, state: \(state)")
    }

    
    func readByte(a0: Bool) -> UInt8 {
        if a0 {
            return interruptMaskRegister
        } else {
            if ocw3.readIRR {
                return interruptRequestRegister
            } else if ocw3.readISR {
                return inServiceRegister
            }
        }
        return 0
    }
}

private let pic1 = PIC()
private let pic2 = PIC()


func pic1IoOut(port: IOPort, operation: VMExit.DataWrite) {
    let a0 = (port & 0x1) == 1
    if case .byte(let byte) = operation {
        pic1.writeByte(byte, a0: a0)
    }
}


func pic1IoIn(port: IOPort, operation: VMExit.DataRead) -> VMExit.DataWrite {
    let a0 = (port & 0x1) == 1
    let byte = pic1.readByte(a0: a0)
    return VMExit.DataWrite(bitWidth: operation.bitWidth, value: UInt64(byte))!
}


func pic2IoOut(port: IOPort, operation: VMExit.DataWrite) {
    let a0 = (port & 0x1) == 1
    if case .byte(let byte) = operation {
        pic2.writeByte(byte, a0: a0)
    }
}


func pic2IoIn(port: IOPort, operation: VMExit.DataRead) -> VMExit.DataWrite {
    let a0 = (port & 0x1) == 1
    let byte = pic2.readByte(a0: a0)
    return VMExit.DataWrite(bitWidth: operation.bitWidth, value: UInt64(byte))!
}


func registerPICHardware() {
    registerIOPort(ports: 0x20...0x21, pic1IoOut, pic1IoIn)
    registerIOPort(ports: 0xA0...0xA1, pic2IoOut, pic2IoIn)
}    
