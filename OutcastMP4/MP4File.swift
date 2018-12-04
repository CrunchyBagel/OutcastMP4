//
//  MP4File.swift
//  Outcast
//
//  Created by Quentin Zervaas on 1/12/18.
//  Copyright © 2018 Crunchy Bagel Pty Ltd. All rights reserved.
//

import Foundation

public class MP4File {
    let localUrl: URL
    
    struct Chapter {
        let title: String // TODO: Determine encoding
        let startTime: TimeInterval
        let duration: TimeInterval
    }
    
    public init(localUrl: URL) throws {
        self.localUrl = localUrl
    }
    
    func assertCorrectFileType(fileHandle: FileHandle) throws {
        fileHandle.seek(toFileOffset: 4)
        
        guard let str = String(data: fileHandle.readData(ofLength: 4), encoding: .isoLatin1), str == "ftyp" else {
            throw ReadError.invalidFileType
        }
    }
}

extension MP4File {
    public enum ReadError: Swift.Error {
        case invalidFileType
        case atomNotFound(String)
        case otherError(String)
        case corrupt(String)
    }
    
    func readChapters() throws -> [Chapter] {
        let fileHandle = try FileHandle(forReadingFrom: self.localUrl)
        
        defer {
            fileHandle.closeFile()
        }

        try self.assertCorrectFileType(fileHandle: fileHandle)

        fileHandle.seek(toFileOffset: 0)
        let moovAtoms = Atom.atoms(fileHandle: fileHandle, endOffset: nil).filter { $0.type == "moov" }
        
        guard let moovAtom = moovAtoms.first else {
            throw ReadError.atomNotFound("moov")
        }
        
        let trackAtoms = moovAtom.subAtoms(fileHandle: fileHandle, type: "trak")
        
        var chapters: [Chapter] = []
        
        for atom in trackAtoms {
            do {
                chapters += try self.chaptersFromTrakAtom(fileHandle: fileHandle, atom: atom)
            }
            catch {
            }
        }
        
        return chapters
    }
    
    private func chaptersFromTrakAtom(fileHandle: FileHandle, atom: Atom) throws -> [Chapter] {
        
        let mdiaAtoms = atom.subAtoms(fileHandle: fileHandle, type: "mdia")
        
        guard mdiaAtoms.count > 0 else {
            throw ReadError.atomNotFound("mdia")
        }
        
        var chapters: [Chapter] = []
        
        for atom in mdiaAtoms {
            do {
                chapters += try self.chaptersFromMdiaAtom(fileHandle: fileHandle, atom: atom)
            }
            catch {
            }
        }
        
        return chapters
    }
    
    private func chaptersFromMdiaAtom(fileHandle: FileHandle, atom: Atom) throws -> [Chapter] {
        
        guard let hdlrAtom = atom.subAtoms(fileHandle: fileHandle, type: "hdlr").first else {
            throw ReadError.atomNotFound("hdlr")
        }
        
        fileHandle.seekToContent(atom: hdlrAtom)
        
        fileHandle.seekForward(count: 8)
        
        guard let subType = String(data: fileHandle.readData(ofLength: 4), encoding: .isoLatin1) else {
            throw ReadError.otherError("Unable to determine subtype")
        }
        
        guard subType == "text" else {
            throw ReadError.otherError("Subtype isn't text, skipping")
        }
        
        guard let minfAtom = atom.subAtoms(fileHandle: fileHandle, type: "minf").first else {
            throw ReadError.atomNotFound("minf")
        }
        
        guard let stblAtom = minfAtom.subAtoms(fileHandle: fileHandle, type: "stbl").first else {
            throw ReadError.atomNotFound("stbl")
        }
        
        return try chaptersFromStblAtom(fileHandle: fileHandle, atom: stblAtom)
    }
    
    private func chaptersFromStblAtom(fileHandle: FileHandle, atom: Atom) throws -> [Chapter] {
        
        guard let stscAtom = atom.subAtoms(fileHandle: fileHandle, type: "stsc").first else {
            throw ReadError.atomNotFound("stsc")
        }
        
        guard let stcoAtom = atom.subAtoms(fileHandle: fileHandle, type: "stco").first else {
            throw ReadError.atomNotFound("stco")
        }
        
        guard let sttsAtom = atom.subAtoms(fileHandle: fileHandle, type: "stts").first else {
            throw ReadError.atomNotFound("stts")
        }
        
        let samplesPerChunk = self.readSamplesPerChunk(fileHandle: fileHandle, atom: stscAtom)
        let chunkOffsets    = self.readChunkOffsets(fileHandle: fileHandle, atom: stcoAtom)
        
        var chapterTitles: [String] = []
        
        for (idx, offset) in chunkOffsets.enumerated() {
            let chunkNumber = idx + 1
            
            var numSamples: UInt32 = 1
            
            for record in samplesPerChunk {
                guard record.firstChunk <= chunkNumber else {
                    break
                }
                
                numSamples = record.numSamples
            }
            
            fileHandle.seek(toFileOffset: UInt64(offset))
            
            for _ in 0 ..< numSamples {
                let length = fileHandle.readUint16()
                let strData = fileHandle.readData(ofLength: Int(length))
                
                guard let str = String(data: strData, encoding: .utf8) else {
                    break
                }
                
                chapterTitles.append(str)
            }
        }
        
        fileHandle.seekToContent(atom: sttsAtom)
        
        fileHandle.seekForward(count: 4)
        let numEntries = fileHandle.readUint32()
        
        guard numEntries == chapterTitles.count else {
            throw ReadError.corrupt("Duration entries count different to chapter title count")
        }
        
        var chapters: [Chapter] = []
        
        var start: TimeInterval = 0
        
        for i in 0 ..< Int(numEntries) {
            fileHandle.seekForward(count: 4)
            let durationMs = fileHandle.readUint32()
            let duration: TimeInterval = Double(durationMs) / 1000
            
            let chapter = Chapter(
                title: chapterTitles[i],
                startTime: start,
                duration: duration
            )
            
            chapters.append(chapter)
            
            start += duration
        }
        
        return chapters
    }
    
    private func readChunkOffsets(fileHandle: FileHandle, atom: Atom) -> [UInt32] {
        fileHandle.seekToContent(atom: atom)
        fileHandle.seekForward(count: 4)
        let numEntries = fileHandle.readUint32()
        
        var chunkOffsets: [UInt32] = []
        
        for _ in 0 ..< numEntries {
            let entryOffset = fileHandle.readUint32()
            chunkOffsets.append(entryOffset)
        }
        
        return chunkOffsets
    }
    
    private struct SamplesPerChunk {
        let firstChunk: UInt32
        let numSamples: UInt32
    }
    
    private func readSamplesPerChunk(fileHandle: FileHandle, atom: Atom) -> [SamplesPerChunk] {
        fileHandle.seekToContent(atom: atom)
        
        fileHandle.seekForward(count: 4)
        let numEntries = fileHandle.readUint32()
        
        var ret: [SamplesPerChunk] = []
        
        for _ in 0 ..< numEntries {
            let firstChunk = fileHandle.readUint32()
            let numSamples = fileHandle.readUint32()
            
            fileHandle.seekForward(count: 4)
            
            ret.append(SamplesPerChunk(firstChunk: firstChunk, numSamples: numSamples))
        }
        
        return ret
    }
}


extension MP4File {
    struct Atom {
        let offset: UInt64
        let size: UInt64
        let type: String
        
        static func parseAtom(fileHandle: FileHandle) -> Atom? {
            let offset = fileHandle.offsetInFile
            
            let length = fileHandle.readUint32()
            
            guard length > 0 else {
                return nil
            }
            
            let typeBytes = fileHandle.readData(ofLength: 4)
            
            guard typeBytes.count == 4 else {
                return nil
            }
            
            guard let type = String(data: typeBytes, encoding: .isoLatin1) else {
                return nil
            }
            
            return Atom(
                offset: offset,
                size: UInt64(length),
                type: type
            )
        }
        
        static func atoms(fileHandle: FileHandle, endOffset: UInt64?) -> [Atom] {
            var atoms: [Atom] = []
            
            while true {
                guard let atom = Atom.parseAtom(fileHandle: fileHandle) else {
                    break
                }
                
                atoms.append(atom)
                
                let offset = atom.offset + atom.size
                
                if let endOffset = endOffset {
                    guard offset < endOffset else {
                        break
                    }
                }
                
                fileHandle.seek(toFileOffset: atom.offset + atom.size)
            }
            
            return atoms
        }
        
        func subAtoms(fileHandle: FileHandle) -> [Atom] {
            fileHandle.seek(toFileOffset: self.offset + 8)
            return Atom.atoms(fileHandle: fileHandle, endOffset: self.offset + self.size)
        }
        
        func subAtoms(fileHandle: FileHandle, type: String) -> [Atom] {
            return self.subAtoms(fileHandle: fileHandle).filter { $0.type == type }
        }
    }
}

extension Data {
    var uint32Value: UInt32 {
        var length: UInt32 = 0
        (self as NSData).getBytes(&length, length: 4)
        
        return length.bigEndian
    }
    
    var uint16Value: UInt16 {
        var length: UInt16 = 0
        (self as NSData).getBytes(&length, length: 2)
        
        return length.bigEndian
    }
}
extension FileHandle {
    func readUint32() -> UInt32 {
        return self.readData(ofLength: 4).uint32Value
    }
    
    func readUint16() -> UInt16 {
        return self.readData(ofLength: 2).uint16Value
    }
    
    func seekToContent(atom: MP4File.Atom) {
        self.seek(toFileOffset: atom.offset + 8)
    }
    
    func seekForward(count: UInt64) {
        self.seek(toFileOffset: self.offsetInFile + count)
    }
}
