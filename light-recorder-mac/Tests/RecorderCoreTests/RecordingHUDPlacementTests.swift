import CoreGraphics
import Testing
@testable import RecorderCore

private let controls = CGSize(width: 238, height: 48)
private let visible = CGRect(x: 0, y: 65, width: 1440, height: 810)

@Test func recordingHUDUsesTheSelectedDisplaysCoordinateSpace() {
    let display = CGRect(x: -1440, y: -180, width: 1440, height: 900)
    let region = RecordingHUDPlacement.screenRect(for: CGRect(x: 190, y: 220, width: 480, height: 300), on: display)
    #expect(region == CGRect(x: -1250, y: 200, width: 480, height: 300))
    let usable = display.insetBy(dx: 10, dy: 35)
    let countdown = RecordingHUDPlacement.countdownFrame(size: CGSize(width: 120, height: 114), in: usable, selection: region)
    let bar = RecordingHUDPlacement.controlsFrame(size: controls, in: usable, selection: region)
    #expect(countdown.midX == region.midX && countdown.midY == region.midY)
    #expect(bar.midX == region.midX && bar.maxY < region.minY)
    #expect(usable.contains(countdown) && usable.contains(bar))
}

@Test func recordingControlsGoAboveTheSelectionWhenTheDockTakesTheSpaceBelow() {
    let region = CGRect(x: 1360, y: 95, width: 78, height: 215)
    let bar = RecordingHUDPlacement.controlsFrame(size: controls, in: visible, selection: region)
    #expect(bar.minY > region.maxY)
    #expect(visible.contains(bar))
    #expect(bar.midX < region.midX) // Keep the whole button on the selected screen.
    #expect(!bar.intersects(region))
}

@Test func recordingControlsRemainReachableForNearlyFullScreenSelections() {
    let region = CGRect(x: 15, y: 0, width: 1330, height: 868)
    let bar = RecordingHUDPlacement.controlsFrame(size: controls, in: visible, selection: region)
    #expect(visible.contains(bar))
    #expect(bar.minY - visible.minY < controls.height)
    #expect(bar.size == controls)
}
