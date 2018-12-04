//
//  main.swift
//  OutcastMP4
//
//  Created by Quentin Zervaas on 3/12/18.
//  Copyright © 2018 Crunchy Bagel. All rights reserved.
//

import Foundation

do {
    let path = URL(fileURLWithPath: "/path/to/file.m4a")
    
    let mp4File = try MP4File(localUrl: path)
    
    let chapters = try mp4File.readChapters()
    
    print("Num chapters: \(chapters.count)")
    
    for (i, chapter) in chapters.enumerated() {
        print("\(i + 1). \(chapter.title)")
    }
}
catch {
    print("\(error)")
}

