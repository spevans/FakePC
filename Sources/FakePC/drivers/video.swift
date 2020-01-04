//
//  video.swift
//  
//
//  Created by Simon Evans on 01/01/2020.
//

import HypervisorKit
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

private enum VideoFunctions: UInt8 {
    case setVideMode = 0
    case setTextCursorShape = 1
    case setCursorPosition = 2
    case getCursorPositionAndShape = 3
    case readLightPen = 4
    case setActiveDisplayPage = 5
    case scrollUp = 6
    case scrollDown = 7
    case readCharacterAndColorAtCursor = 8
    case writeCharacterAndColorAtCursor = 9
    case writeCharacterAtCursor = 0xa
    case setColorOrPalette = 0xb
    case writePixel = 0xc
    case readPixel = 0xd
    case ttyOutput = 0xe
    case getVideoMode = 0xf
    case writeString = 0x13

}

// INT 0x10
func video(_ ax: UInt16, _ vm: VirtualMachine) {
    let function = UInt8(ax >> 8)
    let vcpu = vm.vcpus[0]
    guard let videoFunction = VideoFunctions(rawValue: function) else {
        print("VIDEO: function = 0x\(String(function, radix: 16))")
        print("Unsupported function: 0x\(String(function, radix: 16))")
        return
    }

    switch videoFunction {

        case .setVideMode: fallthrough
        case .setTextCursorShape: fallthrough
        case .setCursorPosition: fallthrough
        case .getCursorPositionAndShape: fallthrough
        case .readLightPen: fallthrough
        case .setActiveDisplayPage: fallthrough
        case .scrollUp: fallthrough
        case .scrollDown: fallthrough
        case .readCharacterAndColorAtCursor: fallthrough
        case .writeCharacterAndColorAtCursor: fallthrough
        case .writeCharacterAtCursor: fallthrough
        case .setColorOrPalette: fallthrough
        case .writePixel: fallthrough

        case .readPixel:
            fatalError("\(videoFunction): not implemented")

        case .ttyOutput:
            let char = UnicodeScalar(vcpu.registers.al)
            //print("TTY Output:", String(vcpu.registers.al, radix: 16))
        print(char, terminator: "")
        fflush(stdout)
        
        case .getVideoMode:
        fallthrough
        case .writeString:
            fatalError("\(videoFunction): not implemented")
    }
}

