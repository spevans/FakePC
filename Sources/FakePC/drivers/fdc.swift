//
//  fdc.swift
//  FakePC
//
//  Created by Simon Evans on 18/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Floppy Drive Controller - handles 2 floppy drives
//

import HypervisorKit


final class FDC: ISAIOHardware {

    struct BiosFloppyType {
        let geometry: Disk.Geometry
    }


    static let floppyGeometries: [Disk.Geometry] = [
        // 160K 5.25" Single Sided Double Density
        Disk.Geometry(sectorsPerTrack: 8, tracksPerHead: 40, heads: 1),
        // 320K 5.25" Double Sided Double Density
        Disk.Geometry(sectorsPerTrack: 8, tracksPerHead: 40, heads: 2),

        // 180K 5.25" Single Sided Double Density
        Disk.Geometry(sectorsPerTrack: 9, tracksPerHead: 40, heads: 1),
        // 360K 5.25" Double Sided Double Density
        Disk.Geometry(sectorsPerTrack: 9, tracksPerHead: 40, heads: 2),

        // 320K 5.25" & 3.5" Single Sided Quad Density
        Disk.Geometry(sectorsPerTrack: 8, tracksPerHead: 80, heads: 1),
        // 640K 5.25" & 3.5" Double Sided Quad Density
        Disk.Geometry(sectorsPerTrack: 8, tracksPerHead: 80, heads: 2),

        // 1200K 1.2M Double Sided High Density
        Disk.Geometry(sectorsPerTrack: 15, tracksPerHead: 80, heads: 2),

        // 360K 3.5" Single Sided Double Density
        Disk.Geometry(sectorsPerTrack: 9, tracksPerHead: 80, heads: 1),

        // 720K 3.5" Double Sided Double Density
        Disk.Geometry(sectorsPerTrack: 9, tracksPerHead: 80, heads: 2),

        // 1440K 1.44M  3.5" Double Sided High Density
        Disk.Geometry(sectorsPerTrack: 18, tracksPerHead: 80, heads: 2),

        // 1680K 3.5" Double Sided High Density
        Disk.Geometry(sectorsPerTrack: 21, tracksPerHead: 80, heads: 2),

        // 1720K 3.5" Double Sided High Density
        Disk.Geometry(sectorsPerTrack: 21, tracksPerHead: 82, heads: 2),

        // 2880K 2.88M 3.5" Double Sided Extended Density
        Disk.Geometry(sectorsPerTrack: 36, tracksPerHead: 80, heads: 2),
    ]


    private(set) var disks: [Disk?] = [nil, nil]
    var mediaChanged = [false, false]
    var diskTypeForFormat: [UInt8] = [0, 0]
    var mediaTypeForFormat: [Disk.Geometry?] = [nil, nil]


    static func parseCommandLineArguments(_ argument: String) -> Disk? {
        return diskForImage(path: argument)
    }


    private static func diskForImage(path: String) -> Disk {
        guard let size = Disk.fileSizeInBytes(path: path) else {
            fatalError("Cant read disk size for \(path)")
        }

        for geometry in floppyGeometries {
            if size == UInt64(geometry.capacity) {
                if let disk = Disk(imageName: path, geometry: geometry, device: .floppy) {
                    return disk
                }
            }
        }
        fatalError("Cant find disk geometry for \(path)")
    }


    init(disk1Path: String? = nil, disk2Path: String? = nil) {
        if let disk1Path = disk1Path {
            try! self.insert(diskPath: disk1Path, intoDrive: 0)
        }
        if let disk2Path = disk2Path {
            try! self.insert(diskPath: disk2Path, intoDrive: 1)
        }
    }

    init(disk1: Disk? = nil, disk2: Disk? = nil) {
        if let disk1 = disk1 {
            guard disk1.isFloppyDisk else { fatalError("Not a floppy disk") }
            disks[0] = disk1
        }

        if let disk2 = disk2 {
            guard disk2.isFloppyDisk else { fatalError("Not a floppy disk") }
            disks[1] = disk2
        }
    }


    func eject(drive: Int) throws {
        guard drive < 2 else { throw DiskError.invalidDrive }
        disks[drive] = nil
        mediaChanged[drive] = true
        diskTypeForFormat[drive] = 0
        mediaTypeForFormat[drive] = nil
    }


    func insert(diskPath: String, intoDrive drive: Int) throws {
        guard drive < 2 else { throw DiskError.invalidDrive }
        let disk = Self.diskForImage(path: diskPath)
        disks[drive] = disk
        logger.debug("FDC: fd\(drive) \(diskPath): \(disk.geometry)")
    }
}
