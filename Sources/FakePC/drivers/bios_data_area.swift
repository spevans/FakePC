//
//  bios_data_area.swift
//  
//
//  Created by Simon Evans on 02/01/2020.
//

// BDA description from http://www.bioscentral.com/misc/bda.htm

import HypervisorKit

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
    @BDAElement(0x17) var keyboardShiftFlags1: UInt8
    @BDAElement(0x18) var keyboardShiftFlags2: UInt8
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
    @BDAElement(0x60) var cursorShare: UInt16
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
    @BDAElement(0x97) var keyboardStatusFlags4: UInt8
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
    diskInit()
}
