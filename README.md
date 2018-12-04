# OutcastMP4
A Swift library to read chapters from MP4/M4A files

# Sample Usage

```swift
let path = URL(fileURLWithPath: "/path/to/file.m4a")
    
let mp4File = try MP4File(localUrl: path)
    
let chapters = try mp4File.readChapters()
    
for (i, chapter) in chapters.enumerated() {
    print("\(i + 1). \(chapter.title)")
}
```
