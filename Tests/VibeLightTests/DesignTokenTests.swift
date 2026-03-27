import AppKit
import Testing
@testable import VibeLight

@Test
func designTokenPanelCornerRadiusIs12() {
    #expect(DesignTokens.Radius.panel == 12)
}

@Test
func designTokenRowCornerRadiusIs6() {
    #expect(DesignTokens.Radius.row == 6)
}

@Test
func designTokenLogoCornerRadiusIs5() {
    #expect(DesignTokens.Radius.logo == 5)
}

@Test
func designTokenIconCornerRadiusIs3() {
    #expect(DesignTokens.Radius.icon == 3)
}

@Test
func designTokenRowHeightWithoutActivityIs56() {
    #expect(DesignTokens.Spacing.rowHeightClosed == 56)
}

@Test
func designTokenRowHeightWithActivityIs74() {
    #expect(DesignTokens.Spacing.rowHeightActive == 74)
}

@Test
func designTokenSearchBarHeightIs64() {
    #expect(DesignTokens.Spacing.searchBarHeight == 64)
}

@Test
func designTokenPanelWidthIs720() {
    #expect(DesignTokens.Spacing.panelWidth == 720)
}

@Test
func sessionTitleFontIsMonospaced14pt() {
    let font = DesignTokens.Font.sessionTitle
    #expect(font.pointSize == 14)
}

@Test
func searchInputFontIs24pt() {
    let font = DesignTokens.Font.searchInput
    #expect(font.pointSize == 24)
}

@Test
func metadataFontIs12pt() {
    let font = DesignTokens.Font.metadata
    #expect(font.pointSize == 12)
}

@Test
func activityFontIsMonospaced11_5pt() {
    let font = DesignTokens.Font.activity
    #expect(font.pointSize == 11.5)
}

@Test
func statusLabelFontIsMonospaced10pt() {
    let font = DesignTokens.Font.statusLabel
    #expect(font.pointSize == 10)
}

@Test
func actionHintFontIsMonospaced11pt() {
    let font = DesignTokens.Font.actionHint
    #expect(font.pointSize == 11)
}

@MainActor
@Test
func neonColorMatchesDesignSpec() {
    let neon = DesignTokens.Color.neon
    let components = neon.usingColorSpace(.sRGB)!
    #expect(abs(components.redComponent - 0.667) < 0.01)
    #expect(abs(components.greenComponent - 1.0) < 0.01)
    #expect(abs(components.blueComponent - 0.863) < 0.01)
}

@MainActor
@Test
func waitingAmberMatchesDesignSpec() {
    let amber = DesignTokens.Color.waitingAmber
    let components = amber.usingColorSpace(.sRGB)!
    #expect(abs(components.redComponent - 1.0) < 0.01)
    #expect(abs(components.greenComponent - 0.788) < 0.01)
    #expect(abs(components.blueComponent - 0.396) < 0.01)
}

@MainActor
@Test
func activityCyanMatchesDesignSpec() {
    let cyan = DesignTokens.Color.activityCyan
    let components = cyan.usingColorSpace(.sRGB)!
    #expect(abs(components.redComponent - 0.490) < 0.01)
    #expect(abs(components.greenComponent - 0.847) < 0.01)
    #expect(abs(components.blueComponent - 0.753) < 0.01)
}
