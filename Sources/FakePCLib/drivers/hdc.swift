//
//  hdc.swift
//  FakePC
//
//  Created by Simon Evans on 18/04/2020.
//  Copyright © 2020 Simon Evans. All rights reserved.
//
//  Hard Drive Controller - handles 2 hard drives
//

import HypervisorKit


public final class HDC: ISAIOHardware {

    public static func parseCommandLineArguments(_ parameters: String) -> Disk? {
        var tracks: Int?
        var heads: Int?
        var sectors: Int?
        var imageFile: String?
        var readOnly = false

        for part in parameters.split(separator: ",") {
            if part == "ro" {
                readOnly = true
                continue
            }
            let option = String(part).split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            guard option.count == 2 else { fatalError("Invalid option: \(parameters)") }
            switch option[0] {
                case "t": if let t = Int(option[1]) { tracks = t }  else { fatalError("Invalid tracks: \(option[1])") }
                case "h": if let h = Int(option[1]) { heads = h  }  else { fatalError("Invalid heads: \(option[1])") }
                case "s": if let s = Int(option[1]) { sectors = s } else { fatalError("Invalid sectors: \(option[1])") }
                case "img": imageFile = String(option[1])
                default: fatalError("Invalid disk option \(option[0])")
            }
        }
        if let tracks = tracks, let sectors = sectors, let heads = heads, let imageFile = imageFile {
            let geometry = Disk.Geometry(sectorsPerTrack: sectors, tracksPerHead: tracks, heads: heads)
            return Disk(imageName: imageFile, geometry: geometry, device: .harddisk, readOnly: readOnly)
        } else {
            fatalError("Disk specifiction \(parameters) is missing track, sector head or imageFile")
        }
    }

    static func parseCommandLineArgumentsFor(cdrom parameters: String) -> Disk? {
        let imageFile = parameters
        guard let fileSize = Disk.fileSizeInBytes(path: imageFile) else { return nil }

        let geometry = Disk.Geometry(totalSize: Int(fileSize), sectorSize: 2048)
        return Disk(imageName: imageFile, geometry: geometry, device: .cdrom, readOnly: true)
    }


    let disks: [Disk?]
    private var lastStatus: [Disk.Status] = [.ok, .ok]

    // Hard drives are already attached at power on so need to be passed to init()
    init(disk1: Disk? = nil, disk2: Disk? = nil) {
        disks = [disk1, disk2]
    }
}
