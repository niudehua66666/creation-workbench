import AppKit
import ImageIO
import Testing
@testable import RecorderCore

@Test func mixedMediaDragContainsSeparateOriginalFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let recording = directory.appendingPathComponent("录屏片段 1.mp4")
    let screenshot = directory.appendingPathComponent("区域截图 #2.png")
    let missing = directory.appendingPathComponent("已移走.png")
    for url in [recording, screenshot] { try Data([1, 2, 3]).write(to: url) }

    let items = MediaFileTransfer.pasteboardItems(for: [recording, screenshot, screenshot, missing, directory])
    let paths = items.compactMap(\.path)
    #expect(paths == [recording.path, screenshot.path])
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    for file in [screenshot, recording] {
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects(MediaFileTransfer.pasteboardItems(for: [file])))
        let original = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL]
        #expect(original?.compactMap(\.path) == [file.path])
    }
    pasteboard.clearContents()
    #expect(pasteboard.writeObjects(items))
    let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL]
    #expect(fileURLs?.compactMap(\.path) == paths)
}

@Test func concurrentScreenshotsKeepBothFullSizePNGFiles() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let context = try #require(CGContext(data: nil, width: 301, height: 193, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(red: 0.1, green: 0.9, blue: 0.2, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 301, height: 193))
    let image = try #require(context.makeImage())
    let date = Date(timeIntervalSince1970: 1_000_000)

    async let first = ScreenshotFile.save(image, in: directory, at: date)
    async let second = ScreenshotFile.save(image, in: directory, at: date)
    let results = try await [first, second]
    #expect(Set(results).count == 2)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
    for url in results {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let png = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(png.width == 301)
        #expect(png.height == 193)
    }
}

@Test func shelfDocksAndRestoresInsideAnOffsetDisplay() {
    let screen = CGRect(x: -1920, y: 90, width: 1920, height: 1040)
    let anchor = CGPoint(x: -1917, y: 1100)
    let side = ShelfPlacement.edge(at: anchor, in: screen)
    #expect(side == .left)
    let tab = ShelfPlacement.frame(size: CGSize(width: 20, height: 66), near: anchor, in: screen, edge: side)
    #expect(tab.minX == screen.minX)
    #expect(screen.contains(tab))
    let restored = ShelfPlacement.frame(size: CGSize(width: 52, height: 52), near: anchor, in: screen)
    #expect(restored.minX > screen.minX)
    #expect(screen.contains(restored))
    #expect(ShelfPlacement.edge(at: CGPoint(x: -4, y: 600), in: screen) == .right)
    #expect(ShelfPlacement.edge(at: CGPoint(x: -800, y: 600), in: screen) == nil)
}

@Test func shelfStaysHiddenUntilCaptureAndHidesAfterCancellation() {
    var shelf = ShelfPresentation()
    shelf.open()
    shelf.drop(at: .right)
    #expect(shelf.appearance == .hidden)

    shelf.setCaptureActive(true)
    #expect(shelf.appearance == .ball)
    shelf.open()
    #expect(shelf.appearance == .expanded)
    shelf.setCaptureActive(false)
    #expect(shelf.appearance == .hidden)
}

@Test func shelfKeepsResultsAvailableUntilDismissed() {
    var shelf = ShelfPresentation()
    shelf.setCaptureActive(true)
    shelf.open()
    shelf.dismiss()
    #expect(shelf.appearance == .ball)

    shelf.drop(at: .right)
    shelf.recordResult()
    shelf.setCaptureActive(false)
    #expect(shelf.appearance == .edge(.right))
    shelf.open()
    #expect(shelf.appearance == .expanded)
    shelf.dismiss()
    #expect(shelf.appearance == .hidden)
    shelf.setCaptureActive(true)
    #expect(shelf.appearance == .ball)
    shelf.setCaptureActive(false)
    #expect(shelf.appearance == .hidden)
}

@Test func shelfDragMovesOrDocksAndOnlyClickOpens() {
    var shelf = ShelfPresentation()
    shelf.setCaptureActive(true)
    shelf.drop(at: nil)
    #expect(shelf.appearance == .ball)

    shelf.open()
    shelf.drop(at: nil)
    #expect(shelf.appearance == .expanded)
    shelf.drop(at: .left)
    #expect(shelf.appearance == .edge(.left))
    shelf.drop(at: .left)
    #expect(shelf.appearance == .edge(.left))
    shelf.drop(at: nil)
    #expect(shelf.appearance == .ball)
    shelf.open()
    #expect(shelf.appearance == .expanded)
}

@Test func shelfDragDoesNotBecomeClickWhenPointerReturnsToStart() {
    let start = CGPoint(x: -800, y: 200)
    var click = ShelfDrag(start: start)
    #expect(click.translation(to: CGPoint(x: -799, y: 201)) == nil)

    var drag = ShelfDrag(start: start)
    #expect(drag.translation(to: CGPoint(x: -794, y: 207)) == CGPoint(x: 6, y: 7))
    #expect(drag.translation(to: start) == .zero)

    var releaseWithoutIntermediateEvent = ShelfDrag(start: start)
    #expect(releaseWithoutIntermediateEvent.translation(to: CGPoint(x: -800, y: 196)) == CGPoint(x: 0, y: -4))
}

@Test func newCaptureReopensShelfAfterDraggingToEitherEdge() {
    for side in [ShelfPlacement.Side.left, .right] {
        var shelf = ShelfPresentation()
        shelf.showShelf()
        shelf.drop(at: side)
        shelf.setCaptureActive(true)
        #expect(shelf.appearance == .edge(side))
        shelf.showShelf()
        shelf.setCaptureActive(false)
        #expect(shelf.appearance == .expanded)
    }
}

@Test func collapsedShelfStaysAtEdgeOnCancellationAndReopensOnSuccess() {
    var shelf = ShelfPresentation()
    shelf.setCaptureActive(true)
    shelf.open()
    shelf.collapse(to: .right)
    shelf.setCaptureActive(false)
    #expect(shelf.appearance == .edge(.right))
    shelf.showShelf()
    #expect(shelf.appearance == .expanded)

    shelf.collapse(to: .left)
    shelf.setCaptureActive(true)
    #expect(shelf.appearance == .edge(.left))
    shelf.showShelf()
    shelf.setCaptureActive(false)
    #expect(shelf.appearance == .expanded)
}
