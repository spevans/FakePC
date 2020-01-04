//
//  disk.swift
//
//
//  Created by Simon Evans on 01/01/2020.
//

import Foundation
import HypervisorKit


private var diskDrives: [UInt8: DiskDrive] = [:]

// Should be stored in BDA @ 0x40:41
private var lastStatus = DiskStatus.ok

private struct DiskDrive {
    let imageURL: URL
    let data: Data
    let sectorSize = 512
    let sectorsPerTrack: Int
    let tracksPerHead: Int
    let heads: Int
    let isReadOnly: Bool
    let isHardDrive = false
    var isFloppyDrive: Bool { !isHardDrive }

    init?(imageName: String, readOnly: Bool = true) {
        print("imageName:", imageName)
        imageURL = URL(fileURLWithPath: imageName, isDirectory: false)
        guard let data = try? Data(contentsOf: imageURL) else {
            print("Cant load")
            return nil
        }
        self.data = data
        heads = 2
        tracksPerHead = 80
        sectorsPerTrack = 18
        let totalSize = heads * tracksPerHead * sectorsPerTrack * sectorSize
        guard totalSize == data.count else {
            print("Image size != floppy size")
            return nil
        }
        isReadOnly = readOnly
    }

    var totalSectors: Int { (data.count + sectorSize - 1) / sectorSize }

    func logicalSector(cx: UInt16, dh: UInt8) -> Int? {
        let head = Int(dh)    // DH = head
        let sector = Int(cx) & 0x3f
        let track = Int(cx) >> 8 | (Int(cx & 0xc0) << 10)
        // print("logicalSector: head: \(head) track: \(track) sector: \(sector)")
        guard sector > 0 && sector <= sectorsPerTrack && track < tracksPerHead && head < heads else {
            return nil
        }
        let logical = (sector - 1) + (head * sectorsPerTrack) + (track * sectorsPerTrack * heads)
        // print("logical: \(logical)")
        return logical
    }

    func readSectors(into buffer: UnsafeMutableRawBufferPointer, fromSector: Int, count: Int) {
        let offset = fromSector * sectorSize
        let size = count * sectorSize
        let range = offset..<(offset + size)
        data.copyBytes(to: buffer, from: range)
    }
}


private enum DiskFunctions: UInt8 {
case resetDisk = 0
case getStatus = 1
case readSectors = 2
    /*    case writeSectors = 3
case verifySectors = 4
case formatTrack = 5
case formatTrackSetBadSectors = 6
case formatDrive = 7*/
case readDriveParameters = 8
    /*    case initialiseHDController = 9*/
case readDASDType = 0x15
    case changeOfDiskStatus = 0x16
}

private enum DiskStatus: UInt8 {
case ok = 0
case invalidCommand = 1
case badSector = 2
case writeProtected = 3
case sectorNotFound = 4
case resetFailed = 5
case changeLineActive = 6
case parameterActivityFailed = 7
case dmaOverrun = 8
case dmaOver64KBoundary = 9
case badSectorDetected = 0xa
case badTrackDetected = 0xb
case mediaTypeNotFound = 0xc
case invalidNumberOfSectors = 0xd
case addressMarkDetected = 0xe
case dmaOutOfRange = 0xf
case dataError = 0x10
case correctedDataError = 0x11
case controllerFailure = 0x20
case seekFailure = 0x40
case driveTimedOut = 0x80
case driveNotReady = 0xAA
case undefinedError = 0xBB
case writeFault = 0xCC
case statusError = 0xE0
case senseOperationFailed = 0xFF


    func setError(_ vcpu: VirtualMachine.VCPU) {
        vcpu.registers.ah = self.rawValue
        vcpu.registers.rflags.carry = (self != .ok)
        lastStatus = self
    }
}


func diskInit() {
#if os(Linux)
    let image = "/home/spse/src/osx/FakePC/FD13FLOP.IMG"
#else
    let image = "/Users/spse/Files/src/osx/FakePC/FD13FLOP.IMG"
#endif

    guard let disk = DiskDrive(imageName: image) else {
        fatalError("Cant load floppy image")
    }
    diskDrives[0] = disk
}


// INT 0x13
func disk(_ ax: UInt16, _ vm: VirtualMachine) {
    let function = UInt8(ax >> 8)
    let vcpu = vm.vcpus[0]
    let dl = vcpu.registers.dl
    let al = vcpu.registers.al

    guard let diskFunction = DiskFunctions(rawValue: function) else {
        fatalError("DISK: function = 0x\(String(function, radix: 16)) drive = \(String(dl, radix: 16))H not implemented")
        //        DiskStatus.invalidCommand.setError(vcpu)
        //        return
    }


    let status: DiskStatus

    switch diskFunction {

    case .resetDisk: // Reset
        status = .ok

    case .getStatus: // Get status
        status = lastStatus

    case .readSectors:
        guard let drive = diskDrives[dl] else {
            status = .invalidCommand
            break
        }

        guard let startSector = drive.logicalSector(cx: vcpu.registers.cx, dh: vcpu.registers.dh) else {
            status = .invalidCommand
            break
        }
        let sectorCount = Int(al)
        guard sectorCount > 0 && sectorCount <= 63 else {
            status = .invalidNumberOfSectors
            break
        }

        let size = sectorCount * drive.sectorSize
        // Check there is enough space from the buffer to end for segment  (boundary overflow)
        let bx = Int(vcpu.registers.bx)
        guard 0x10000 - bx >= size else {
            status = .dmaOver64KBoundary
            break
        }
        guard startSector + sectorCount <= drive.totalSectors else {
            status = .invalidNumberOfSectors
            break
        }
        let offset = Int(vcpu.registers.es.base) + bx
        //print("Copying \(size) bytes to 0x\(String(offset, radix: 16))")
        let ptr = vm.memoryRegions[0].rawBuffer.baseAddress!.advanced(by: offset)
        let buffer = UnsafeMutableRawBufferPointer(start: ptr, count: size)
        drive.readSectors(into: buffer, fromSector: startSector, count: sectorCount)
//        print("Reading \(sectorCount) sectors from \(startSector) -> \(hexNum(vcpu.registers.es.selector, width: 4)):\(hexNum(bx, width: 4))")

        status = .ok

    case .readDriveParameters:
        guard let drive = diskDrives[dl] else {
            status = .invalidCommand
            break
        }

        showRegisters(vcpu)
        vcpu.registers.bl = 04
        let cylinders = drive.tracksPerHead
        vcpu.registers.ch = UInt8(cylinders & 0xff)
        vcpu.registers.cl = UInt8(drive.sectorsPerTrack & 0x3f) | (UInt8(cylinders >> 6) & 0xc0)
        vcpu.registers.dh = UInt8(drive.heads - 1)
        vcpu.registers.dl = 1
        status = .ok

    case .readDASDType:
        if let drive = diskDrives[dl] {
            vcpu.registers.ah = 2
            if drive.isHardDrive {
                let sectors = UInt32(drive.totalSectors)
                vcpu.registers.cx = UInt16(sectors >> 16)
                vcpu.registers.dx = UInt16(sectors & 0xffff)
            }
        } else {
            vcpu.registers.ah = 0
            vcpu.registers.rflags.carry = false
        }
        lastStatus = .ok
        return

    case .changeOfDiskStatus:
        status = .ok
    }


    status.setError(vcpu)
}
