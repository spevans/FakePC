//
//  serial.swift
//  FakePC
//
//  Created by Simon Evans on 17/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Emulation of a serial port and BIOS INT 14h calls.
//

import Foundation
import HypervisorKit


final class Serial: ISAIOHardware {

    private let basePort: IOPort
    private let irq: UInt8

    // basePort + 0, basePort + 1 when DLAB = 1
    private var divisorLo: UInt8 = 1
    private var divisorHi: UInt8 = 0
    private var divisor: UInt16 { UInt16(divisorHi) << 8 | UInt16(divisorLo) }

    // +1 when DLAB = 0
    private var interruptEnableRegister: UInt8 = 0

    // +2 Read
    private var interruptIdentificationRegister: UInt8 = 0
    // +2 Write
    private var fifoControlRegister: UInt8 = 0
    // +3
    private var lineControlRegister: UInt8 = 0
    // +4
    private var modemControlRegister: UInt8 = 0
    // +5
    private var lineStatusRegister: UInt8 = 0x60 // Transmitter holding register empty, ready to transmit
    // +6
    private var modemStatusRegister: UInt8 = 0
    // +7
    private var scratchPad: UInt8 = 0

    private var txFifo = Array<UInt8>(repeating: 0, count: 16)
    private var rxFifo = Array<UInt8>(repeating: 0, count: 16)

    private var dlab: Bool { lineControlRegister & 0x80 == 0x80 }
    private var output = ""


    init(basePort: IOPort, irq: UInt8) {
        self.basePort = basePort
        self.irq = irq
    }


    func ioOut(port: IOPort, operation: VMExit.DataWrite) throws {
        logger.debug("SERIAL: port: 0x\(String(port, radix: 16)), value: \(operation)")
        guard case .byte(let byte) = operation else {
            logger.debug("SERIAL: Ignoring non byte write")
            return
        }

        let offset = port - basePort
        switch offset {
            case 0: if dlab {
                divisorLo = byte
            } else {
                // TX byte
                output.append(Character(Unicode.Scalar(byte)))
                logger.debug("SERIAL OUTPUT \(output)")
                if byte == 0xa { output = "" }
            }

            case 1: if dlab {
                divisorHi = byte
            } else {
                interruptEnableRegister = byte
            }

            case 2: fifoControlRegister = byte
            case 3: lineControlRegister = byte
            case 4: modemControlRegister = byte
            case 5: break   // Read only
            case 6: break   // Read only
            case 7: scratchPad = byte
            default: fatalError("SERIAL: Unexpected write to 0x\(String(port, radix: 16))")
        }
    }


    func ioIn(port: IOPort, operation: VMExit.DataRead) -> VMExit.DataWrite {
        let result: VMExit.DataWrite

        let offset = port - basePort
        switch offset {
            case 0: if dlab {
                result = .byte(divisorLo)
            } else {
                // RX byte
                result = .byte(rxFifo[0])
            }

            case 1: if dlab {
                result = .byte(divisorHi)
            } else {
                result = .byte(interruptEnableRegister)
            }

            case 2: result = .byte(interruptIdentificationRegister)
            case 3: result = .byte(lineControlRegister)
            case 4: result = .byte(modemControlRegister)
            case 5: result = .byte(lineStatusRegister)
            case 6: result = .byte(modemStatusRegister)
            case 7: result = .byte(scratchPad)
            default: fatalError("SERIAL: Unexpected read 0x\(String(port, radix: 16))")
        }
        return result
    }
}


// INT 14h BIOS Interface
extension Serial {

    private enum BIOSFunction: UInt8 {
        case initialisePort = 0
        case sendCharacter = 1
        case receiveCharacter = 2
        case getPortStatus = 3
        case extendedInitialise = 4
        case extendedPortControl = 5
    }


    func biosCall(_ ax: UInt16, _ vm: VirtualMachine) {
        let function = UInt8(ax >> 8)
        let vcpu = vm.vcpus[0]

        guard let serialFunction = BIOSFunction(rawValue: function) else {
            fatalError("SERIAL: unknown function 0x\(String(function, radix: 16))")
        }

        switch serialFunction {
            case .initialisePort:       fallthrough
            case .sendCharacter:        fallthrough
            case .receiveCharacter:     fallthrough
            case .getPortStatus:        fallthrough
            case .extendedInitialise:   fallthrough
            case .extendedPortControl:  logger.debug("SERIAL: \(serialFunction) not implemented")
        }
        vcpu.registers.rflags.carry = true
    }
}
