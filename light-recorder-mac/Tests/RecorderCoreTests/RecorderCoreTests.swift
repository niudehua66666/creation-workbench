import Foundation
import CoreGraphics
import Testing
@testable import RecorderCore

@Test func reverseDragKeepsLocalTopLeftCoordinates() {
    let rect = CaptureGeometry.selection(from: CGPoint(x: 800, y: 500), to: CGPoint(x: 100, y: 50), bounds: CGRect(x: 0, y: 0, width: 1440, height: 900))
    #expect(rect == CGRect(x: 100, y: 50, width: 700, height: 450))
}

@Test func selectionClipsAtDisplayEdges() {
    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let rect = CaptureGeometry.selection(from: CGPoint(x: 1000, y: 600), to: CGPoint(x: 1700, y: 1000), bounds: bounds)
    #expect(rect == CGRect(x: 1000, y: 600, width: 440, height: 300))
}

@Test func accidentalClicksDoNotStartRecordings() {
    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
    #expect(CaptureGeometry.selection(from: .zero, to: CGPoint(x: 5, y: 7), bounds: bounds) == nil)
    #expect(CaptureGeometry.selection(from: .zero, to: CGPoint(x: 100, y: 10), bounds: bounds) == nil)
    #expect(CaptureGeometry.selection(from: CGPoint(x: -200, y: -100), to: CGPoint(x: -30, y: -40), bounds: bounds) == nil)
}

@Test func retinaVideoFitsH264Dimensions() {
    #expect(CaptureGeometry.videoSize(points: CGSize(width: 1440, height: 900), scale: 2, maximumEdge: 1920) == CGSize(width: 1920, height: 1200))
    #expect(CaptureGeometry.videoSize(points: CGSize(width: 1512, height: 982), scale: 2, maximumEdge: 3840) == CGSize(width: 3024, height: 1964))
    #expect(CaptureGeometry.videoSize(points: CGSize(width: 601, height: 401), scale: 1, maximumEdge: 1920) == CGSize(width: 600, height: 400))
}

@Test func portraitAndInvalidSizesRemainSafe() {
    let size = CaptureGeometry.videoSize(points: CGSize(width: 1080, height: 1920), scale: 2, maximumEdge: 1920)
    #expect(size == CGSize(width: 1080, height: 1920))
    #expect(CaptureGeometry.videoSize(points: .zero, scale: 2, maximumEdge: 1920) == CGSize(width: 2, height: 2))
}

@Test func filenamesDoNotOverwriteExistingRecordings() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let date = Date(timeIntervalSince1970: 1_000_000)
    let first = try RecordingDestination(directory: directory, date: date)
    let second = try RecordingDestination(directory: directory, date: date)
    #expect(first.temporaryURL != second.temporaryURL)
    try Data("first video".utf8).write(to: first.temporaryURL)
    let firstURL = try first.finish()
    try Data("second video".utf8).write(to: second.temporaryURL)
    let secondURL = try second.finish()
    #expect(firstURL != secondURL)
    #expect(secondURL.lastPathComponent.contains("(2)"))
    #expect(try Data(contentsOf: firstURL) == Data("first video".utf8))
    #expect(try Data(contentsOf: secondURL) == Data("second video".utf8))
    #expect(!FileManager.default.fileExists(atPath: first.temporaryURL.path))
}

@Test func emptyFileIsNeverReportedAsComplete() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = try RecordingDestination(directory: directory)
    try Data().write(to: target.temporaryURL)
    #expect(throws: (any Error).self) { try target.finish() }
    #expect(target.preserveInterrupted() == nil)
    #expect(!FileManager.default.fileExists(atPath: target.temporaryURL.path))
}

@Test func interruptedFileIsRetainedWithDistinctName() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = try RecordingDestination(directory: directory)
    let bytes = Data("recoverable partial recording".utf8)
    try bytes.write(to: target.temporaryURL)
    let recovered = try #require(target.preserveInterrupted())
    #expect(recovered.lastPathComponent.hasPrefix("未完成录制-"))
    #expect(try Data(contentsOf: recovered) == bytes)
}

@Test func invalidDestinationFailsBeforeRecording() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("not a folder".utf8).write(to: file)
    #expect(throws: (any Error).self) { try RecordingDestination(directory: file) }
}

@Test func timerHandlesLongRecordings() {
    #expect(durationLabel(-1) == "00:00")
    #expect(durationLabel(65) == "01:05")
    #expect(durationLabel(3661) == "1:01:01")
    #expect(durationLabel(.infinity) == "00:00")
}
