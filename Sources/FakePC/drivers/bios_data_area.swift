//
//  bios_data_area.swift
//  FakePC
//
//  Created by Simon Evans on 02/01/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  BIOS Data Area (BDA) holds working data set used by the BIOS ROM.
//
//  BDA description from http://www.bioscentral.com/misc/bda.htm

import HypervisorKit


struct KeyboardStatusFlags1 {
    private var value: BitArray8
    var rawValue: UInt8 { value.rawValue }

    init(_ rawValue: UInt8) {
        value = BitArray8(rawValue)
    }

    var rightShiftKeyDown: Bool {
        get { value[0] != 0 }
        set { value[0] = newValue ? 1 : 0 }
    }
    var leftShiftKeyDown:  Bool {
        get { value[1] != 0 }
        set { value[1] = newValue ? 1 : 0 }
    }
    var controlKeyDown: Bool {
        get { value[2] != 0 }
        set { value[2] = newValue ? 1 : 0 }
    }
    var altKeyDown: Bool {
        get { value[3] != 0 }
        set { value[3] = newValue ? 1 : 0 }
    }
    var scrollLockOn: Bool {
        get { value[4] != 0 }
        set { value[4] = newValue ? 1 : 0 }
    }
    var numLockOn: Bool {
        get { value[5] != 0 }
        set { value[5] = newValue ? 1 : 0 }
    }
    var capsLockOn: Bool {
        get { value[6] != 0 }
        set { value[6] = newValue ? 1 : 0 }
    }
    var insertOn: Bool {
        get { value[7] != 0 }
        set { value[7] = newValue ? 1 : 0 }
    }
}


struct KeyboardStatusFlags2 {
    private var value: BitArray8
    var rawValue: UInt8 { value.rawValue }

    init(_ rawValue: UInt8) {
        value = BitArray8(rawValue)
    }

    var leftControlKeyDown: Bool {
        get { value[0] != 0 }
        set { value[0] = newValue ? 1 : 0 }
    }
    var leftAltKeyDown:  Bool {
        get { value[1] != 0 }
        set { value[1] = newValue ? 1 : 0 }
    }
    var sysReqKeyDown: Bool {
        get { value[2] != 0 }
        set { value[2] = newValue ? 1 : 0 }
    }
    var pauseKeyIsActive: Bool {
        get { value[3] != 0 }
        set { value[3] = newValue ? 1 : 0 }
    }
    var scrollLockKeyDown: Bool {
        get { value[4] != 0 }
        set { value[4] = newValue ? 1 : 0 }
    }
    var numLockKeyDown: Bool {
        get { value[5] != 0 }
        set { value[5] = newValue ? 1 : 0 }
    }
    var capsLockLeyDown: Bool {
        get { value[6] != 0 }
        set { value[6] = newValue ? 1 : 0 }
    }
    var insertKeyDown: Bool {
        get { value[7] != 0 }
        set { value[7] = newValue ? 1 : 0 }
    }
}

struct KeyboardStatusFlags3 {
    private var value: BitArray8
    var rawValue: UInt8 { value.rawValue }

    init(_ rawValue: UInt8) {
        value = BitArray8(rawValue)
    }

    var lastScanCodeWasE1: Bool {
        get { value[0] != 0 }
        set { value[0] = newValue ? 1 : 0 }
    }
    var lastScanCodeWasE0:  Bool {
        get { value[1] != 0 }
        set { value[1] = newValue ? 1 : 0 }
    }
    var rightControlKeyDown: Bool {
        get { value[2] != 0 }
        set { value[2] = newValue ? 1 : 0 }
    }
    var rightAltKeyDown: Bool {
        get { value[3] != 0 }
        set { value[3] = newValue ? 1 : 0 }
    }
    var hasExtendedKeyboard: Bool {
        get { value[4] != 0 }
        set { value[4] = newValue ? 1 : 0 }
    }
    var forcedNumlockIsOn: Bool {
        get { value[5] != 0 }
        set { value[5] = newValue ? 1 : 0 }
    }
    var lastCodeWasFirstIDCharacter: Bool {
        get { value[6] != 0 }
        set { value[6] = newValue ? 1 : 0 }
    }
    var readingTwoByteKeyboardIDInProgress: Bool {
        get { value[7] != 0 }
        set { value[7] = newValue ? 1 : 0 }
    }
}


struct KeyboardStatusFlags4 {
    private var value: BitArray8
    var rawValue: UInt8 { value.rawValue }

    init(_ rawValue: UInt8) {
        value = BitArray8(rawValue)
    }

    var scrollLockLEDOn: Bool {
        get { value[0] != 0 }
        set { value[0] = newValue ? 1 : 0 }
    }
    var numlockLEDOn:  Bool {
        get { value[1] != 0 }
        set { value[1] = newValue ? 1 : 0 }
    }
    var capsLockLEDOn: Bool {
        get { value[2] != 0 }
        set { value[2] = newValue ? 1 : 0 }
    }

    // Bit3 Reserved

    var ackReceived: Bool {
        get { value[4] != 0 }
        set { value[4] = newValue ? 1 : 0 }
    }
    var resendCodeReceived: Bool {
        get { value[5] != 0 }
        set { value[5] = newValue ? 1 : 0 }
    }
    var ledUpdateInProgress: Bool {
        get { value[6] != 0 }
        set { value[6] = newValue ? 1 : 0 }
    }
    var keyboardTransmitError: Bool {
        get { value[7] != 0 }
        set { value[7] = newValue ? 1 : 0 }
    }
}


struct BDA {
    static var ptr: UnsafeMutableRawPointer!

    @propertyWrapper
    struct BDAElement<T: BinaryInteger> {
        let offset: Int

        init(_ offset: Int) {
            self.offset = offset
        }

        var wrappedValue: T {
            get { BDA.ptr.load(fromByteOffset: offset, as: T.self) }
            set { BDA.ptr.unalignedStoreBytes(of: newValue, toByteOffset: offset, as: T.self) }
        }
    }

    @BDAElement(0) var com1IOAddress: UInt16
    @BDAElement(2) var com2IOAddress: UInt16
    @BDAElement(4) var com3IOAddress: UInt16
    @BDAElement(6) var com4IOAddress: UInt16
    @BDAElement(8) var lpt1IOAddress: UInt16
    @BDAElement(0xA) var lpt2IOAddress: UInt16
    @BDAElement(0xC) var lpt3IOAddress: UInt16
    @BDAElement(0xE) var post1: UInt16
    @BDAElement(0x10) var equipment: UInt16
    @BDAElement(0x12) var post2: UInt8
    @BDAElement(0x13) var memorySize: UInt16
    @BDAElement(0x15) var errorCodes: UInt16

    @BDAElement(0x17) var keyboardStatusFlags1: UInt8
    var keyboardStatusFlags1Flags: KeyboardStatusFlags1 {
        get { KeyboardStatusFlags1(keyboardStatusFlags1) }
        set { keyboardStatusFlags1 = newValue.rawValue }
    }

    @BDAElement(0x18) var keyboardStatusFlags2: UInt8
    var keyboardStatusFlags2Flags: KeyboardStatusFlags2 {
        get { KeyboardStatusFlags2(keyboardStatusFlags2) }
        set { keyboardStatusFlags2 = newValue.rawValue }
    }

    @BDAElement(0x19) var altNumpadWorkArea: UInt8
    @BDAElement(0x1A) var keyboardBufferHead: UInt16
    @BDAElement(0x1C) var keyboardBufferTail: UInt16
    // .
    // 32 bytes of keyboard buffer
    // .
    @BDAElement(0x3E) var floppyDriveCalibrationStatus: UInt8
    @BDAElement(0x3F) var floppyDriveMotorStatus: UInt8
    @BDAElement(0x40) var floppyDriveMotorTimeout: UInt8
    @BDAElement(0x41) var floppyDriveStatus: UInt8
    @BDAElement(0x42) var driveControllerStatusReg0: UInt8
    @BDAElement(0x43) var driveControllerStatusReg1: UInt8
    @BDAElement(0x44) var driveControllerStatusReg2: UInt8
    @BDAElement(0x45) var floppyControllerCylinder: UInt8
    @BDAElement(0x46) var floppyControllerHead: UInt8
    @BDAElement(0x47) var floppyControllerSector: UInt8
    @BDAElement(0x48) var floppyControllerBytesWritten: UInt8
    @BDAElement(0x49) var activeVideoMode: UInt8
    @BDAElement(0x4A) var textColumnsPerRow: UInt16
    @BDAElement(0x4C) var activeVideoPageSize: UInt16
    @BDAElement(0x4E) var activeVideoPageOffset: UInt16
    @BDAElement(0x50) var cursorPositionForPage0: UInt16
    @BDAElement(0x52) var cursorPositionForPage1: UInt16
    @BDAElement(0x54) var cursorPositionForPage2: UInt16
    @BDAElement(0x56) var cursorPositionForPage3: UInt16
    @BDAElement(0x58) var cursorPositionForPage4: UInt16
    @BDAElement(0x5A) var cursorPositionForPage5: UInt16
    @BDAElement(0x5C) var cursorPositionForPage6: UInt16
    @BDAElement(0x5E) var cursorPositionForPage7: UInt16
    @BDAElement(0x60) var cursorShape: UInt16
    @BDAElement(0x62) var activeVideoPage: UInt8
    @BDAElement(0x63) var videoIOAddress: UInt16
    @BDAElement(0x65) var videoInternalModeReg: UInt8
    @BDAElement(0x66) var videoColourPalette: UInt8
    @BDAElement(0x67) var videoRomOffset: UInt16
    @BDAElement(0x69) var videoRomSegment: UInt16
    @BDAElement(0x6B) var lastInterrupt: UInt8
    @BDAElement(0x6C) var timerCount: UInt32
    @BDAElement(0x70) var timer24HourFlag: UInt8
    @BDAElement(0x71) var keyboardCtrlBreakFlag: UInt8
    @BDAElement(0x72) var postSoftResetFlag: UInt16
    @BDAElement(0x74) var statusLastHardDiskOperation: UInt8
    @BDAElement(0x75) var numberOfHardDrives: UInt8
    @BDAElement(0x76) var hardDriveControlByte: UInt8
    @BDAElement(0x78) var lpt1Timeout: UInt8
    @BDAElement(0x79) var lpt2Timeout: UInt8
    @BDAElement(0x7A) var lpt3Timeout: UInt8
    @BDAElement(0x7B) var virtualDMASupport: UInt8
    @BDAElement(0x7C) var com1Timeout: UInt8
    @BDAElement(0x7D) var com2Timeout: UInt8
    @BDAElement(0x7E) var com3Timeout: UInt8
    @BDAElement(0x7F) var com4Timeout: UInt8
    @BDAElement(0x80) var keyboardBufferStartAddress: UInt16
    @BDAElement(0x82) var keyboardBufferEndAddress: UInt16
    @BDAElement(0x84) var numberOfVideoRows: UInt8
    @BDAElement(0x85) var scanLinesPerCharacter: UInt16
    @BDAElement(0x87) var videoDisplayAdaptorOption: UInt8
    @BDAElement(0x88) var videoDisplayAdaptorSwitches: UInt8
    @BDAElement(0x89) var vgaFlags1: UInt8
    @BDAElement(0x8A) var vgaFlags2: UInt8


    @BDAElement(0x96) var keyboardStatusFlags3: UInt8
    var keyboardStatusFlags3Flags: KeyboardStatusFlags3 {
        get { KeyboardStatusFlags3(keyboardStatusFlags3) }
        set { keyboardStatusFlags3 = newValue.rawValue }
    }

    @BDAElement(0x97) var keyboardStatusFlags4: UInt8
    var keyboardStatusFlags4Flags: KeyboardStatusFlags4 {
        get { KeyboardStatusFlags4(keyboardStatusFlags4) }
        set { keyboardStatusFlags4 = newValue.rawValue }
    }
}


func setupBDA(_ vm: VirtualMachine) throws {
    BDA.ptr = try vm.memory(at: PhysicalAddress(RawAddress(0x400)), count: 256)

    var bda = BDA()

    var equipment = BitArray16(0)
    equipment[14...15] = 1  // parallel ports
    equipment[9...11] = 0   // serial ports
    equipment[6...7] = 1    // floppy drives
    equipment[4...5] = 0b11 // video mode = 80x25 monochrome
    equipment[2] = 0        // no PS/2 mouse
    equipment[1] = 1        // math co-processor installed
    equipment[0] = 1        // boot floppy present

    bda.equipment = equipment.rawValue
    bda.memorySize = 640

    bda.keyboardBufferHead = 0x1E
    bda.keyboardBufferTail = 0x1E
    bda.keyboardBufferStartAddress = 0x1E
    bda.keyboardBufferEndAddress = 0x3C

    if let rtc = ISA.rtc {
        bda.timerCount = (rtc.secondsSinceMidnight() * 182) / 10
    }
}
