//
//  Int10Video.swift
//  FakePC
//
//  Created by Simon Evans on 31/03/2021.
//  Copyright © 2021 Simon Evans. All rights reserved.
//
//  INT 10H BIOS Video services.
//

import HypervisorKit

extension Video {

    private enum BIOSFunction: UInt8 {
        case setVideoMode = 0
        case setTextCursorShape = 1
        //    case setCursorPosition = 2
        //    case getCursorPositionAndShape = 3
        //    case readLightPen = 4
        //    case setActiveDisplayPage = 5
        case scrollUp = 6
        case scrollDown = 7
        case readCharacterAndColorAtCursor = 8
        case writeCharacterAndColorAtCursor = 9
        case writeCharacterAtCursor = 0xa
        case setColorOrPalette = 0xb
        case writePixel = 0xc
        case readPixel = 0xd
        case ttyOutput = 0xe
        //    case getVideoState = 0xf
        case paletteRegisterControl = 0x10
        case characterGeneratorControl = 0x11
        case videoSubsystemControl = 0x12
        case writeString = 0x13
    }


    func biosCall(function: UInt8, registers: VirtualMachine.VCPU.Registers, _ vm: VirtualMachine) {
        let al = registers.al

        let vcpu = vm.vcpus[0]
        guard let videoFunction = BIOSFunction(rawValue: function) else {
            logger.debug("VIDEO: function = 0x\(String(function, radix: 16))")
            logger.debug("Unsupported function: 0x\(String(function, radix: 16))")
            return
        }

        switch videoFunction {

            case .setVideoMode:
                setVideo(mode: al)

            case .setTextCursorShape:
                let cl = registers.cl & 0b11111
                let ch = registers.ch & 0b11111
                logger.debug("VIDEO: set cursor shape start: \(ch) end: \(cl)")
                break

            case .scrollUp:
                let bh = registers.bh
                let cl = registers.cl
                let ch = registers.ch
                let dl = registers.dl
                let dh = registers.dh
                scrollUp(lines: al, color: bh, startRow: ch, startColumn: cl, endRow: dh, endColumn: dl)

            case .scrollDown:
                let bh = registers.bh
                let cl = registers.cl
                let ch = registers.ch
                let dl = registers.dl
                let dh = registers.dh
                scrollDown(lines: al, color: bh, startRow: ch, startColumn: cl, endRow: dh, endColumn: dl)

            case .readCharacterAndColorAtCursor:
                let (color, character) = readCharacterAndColorAtCursor(page: registers.bh)
                registers.ah = color
                registers.al = character

            case .writeCharacterAndColorAtCursor:
                let bl = registers.bl
                let bh = registers.bh
                let cx = registers.cx
                writeCharacterAndColorAtCursor(character: al, page: bh, color: bl, count: cx)

            case .writeCharacterAtCursor:
                let bh = registers.bh
                let cx = registers.cx
                let color = screenMode.isTextMode ? 0x7 : registers.bl
                writeCharacterAndColorAtCursor(character: al, page: bh, color: color, count: cx)

            case .setColorOrPalette: fallthrough
            case .writePixel: fallthrough
            case .readPixel:
                fatalError("\(videoFunction): not implemented")

            case .ttyOutput:
                let bl = registers.bl
                let bh = registers.bh
                ttyOutput(character: al, page: bh, color: bl)

            case .paletteRegisterControl: fallthrough

            case .characterGeneratorControl:
                vcpu.showRegisters()
                fatalError("\(videoFunction): not implemented")

            case .videoSubsystemControl:
                let bl = registers.bl
                switch bl {
                    case 0x10:
                        registers.bh = screenMode.isColor ? 0 : 1
                        registers.bl = 3  // 256k
                        registers.ch = 0  // feature bits
                        registers.cl = 0  //

                    default:
                        fatalError("\(videoFunction): not implemented")
                }

            case .writeString:
                logger.debug("Ignoring .writeString")
                break
        /*            let bl = registers.bl
             let bh = registers.bh
             let cx = registers.cx
             let dh = registers.dh
             let dl = registers.dl
             let es = registers.es
             let bp = registers.bp
             let stringAddress = PhysicalAddress(es.base << 4 + UInt(bp))

             let rawPtr = try! vm.memory(at: stringAddress, count: UInt64(cx))
             for x in 0..<cx {
             let idx =  (al & 2 == 2) ? x * 2 : x
             let ch = rawPtr.load(fromByteOffset: Int(idx), as: UInt8.self)
             debugLog(String(Unicode.Scalar(ch)))
             }

             fatalError("\(videoFunction): not implemented")*/
        }
    }
}
