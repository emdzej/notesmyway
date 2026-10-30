//
//  ThemeTests.swift
//  NmwUITests
//
//  Editor themes: JSON round trip, the built-ins' colors all parse, and
//  applying a theme fills the engine configuration.
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
import MarkdownEngine
import Testing
@testable import NmwUI

@MainActor
@Suite("Editor themes")
struct ThemeTests {

    @Test func hexColorsParse() {
        #expect(EditorTheme.parse("#FF0000") != nil)
        #expect(EditorTheme.parse("0f0") != nil)
        #expect(EditorTheme.parse("#11223380") != nil)
        #expect(EditorTheme.parse("#12") == nil)
        #expect(EditorTheme.parse("blue") == nil)
    }

    @Test func everyBuiltInColorParses() {
        for theme in EditorTheme.builtIn {
            for colors in [theme.light, theme.dark] {
                let data = try! JSONEncoder().encode(colors)
                let dict = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
                var values = dict.compactMap { $0.value as? String }
                if let source = dict["source"] as? [String: Any] { values += source.compactMap { $0.value as? String } }
                for value in values { #expect(EditorTheme.parse(value) != nil, "\(theme.id): \(value)") }
            }
        }
        #expect(Set(EditorTheme.builtIn.map(\.id)).count == EditorTheme.builtIn.count)
    }

    @Test func jsonRoundTrip() throws {
        let json = ThemeStore.json(EditorTheme.paper)
        let decoded = try JSONDecoder().decode(EditorTheme.self, from: Data(json.utf8))
        #expect(decoded == EditorTheme.paper)
    }

    @Test func minimalJSONDecodes() throws {
        let json = ##"{"id":"mine","name":"Mine","light":{"link":"#336699"},"dark":{}}"##
        let theme = try JSONDecoder().decode(EditorTheme.self, from: Data(json.utf8))
        var engine = MarkdownEditorTheme.default
        theme.apply(to: &engine)
        #expect(engine.background == nil)
        #expect(engine.headingText == nil)
    }

    @Test func applyFillsTheEngineTheme() {
        var engine = MarkdownEditorTheme.default
        EditorTheme.solarized.apply(to: &engine)
        #expect(engine.background != nil)
        #expect(engine.headingText != nil)
        #expect(engine.tableBorder != nil)
        #expect(engine.inlineCodeText != nil)
        var source = SourceModeStyle.default
        EditorTheme.solarized.apply(to: &source)
        #expect(source.background != nil)
        #expect(source.listMarkerColor != nil)
    }

    @Test func fontNamesMapToEngineTokens() {
        #expect(EditorTheme.engineFontName("serif") == MarkdownFontName.serif)
        #expect(EditorTheme.engineFontName("Mono") == MarkdownFontName.monospaced)
        #expect(EditorTheme.engineFontName("Menlo-Regular") == "Menlo-Regular")
    }

    @Test func appearanceAppliesThemeFontsAndRevision() {
        let defaults = UserDefaults(suiteName: "nmw.tests.\(UUID().uuidString)")!
        let appearance = EditorAppearance(defaults: defaults)
        appearance.themeID = "paper"
        appearance.lineSpacing = 1.5
        var configuration = MarkdownEditorConfiguration.default
        appearance.apply(to: &configuration, highlightsCode: false)
        #expect(appearance.fontName == MarkdownFontName.serif)
        #expect(configuration.theme.background != nil)
        #expect(configuration.paragraph.lineHeightExtraSpacing > MarkdownEditorConfiguration.default.paragraph.lineHeightExtraSpacing)
        let before = configuration.appearanceRevision
        appearance.font = .mono
        #expect(appearance.fontName == MarkdownFontName.monospaced)
        var again = MarkdownEditorConfiguration.default
        appearance.apply(to: &again, highlightsCode: false)
        #expect(again.appearanceRevision != before)
        #expect(again.theme.headingFontName == nil)
        // Settings persist.
        #expect(EditorAppearance(defaults: defaults).themeID == "paper")
    }

    // MARK: Installing

    @Test func lenientDecodingFillsIDAndPalettes() throws {
        let theme = try ThemeStore.validate(Data(##"{"name":"Ocean Night!","modes":["dark"],"dark":{"background":"#001122"}}"##.utf8))
        #expect(theme.id == "ocean-night")
        #expect(theme.light == EditorTheme.Colors())
        #expect(theme.requiredScheme == .dark)
        #expect(!theme.supportsLight && theme.supportsDark)
    }

    @Test func modesDefaultToBoth() {
        #expect(EditorTheme.paper.requiredScheme == nil)
        #expect(EditorTheme.builtIn.allSatisfy { $0.supportsLight && $0.supportsDark })
    }

    @Test func validationExplainsWhatIsWrong() {
        func reason(_ json: String) -> String? {
            do { _ = try ThemeStore.validate(Data(json.utf8)); return nil } catch { return error.localizedDescription }
        }
        #expect(reason("not json")?.contains("valid JSON") == true)
        #expect(reason(##"{"id":"x"}"##)?.contains("name") == true)
        #expect(reason(##"{"name":"X","light":{"link":"blue"}}"##)?.contains("light.link") == true)
        #expect(reason(##"{"name":"X","dark":{"source":{"code":"#12"}}}"##)?.contains("dark.source.code") == true)
        #expect(reason(##"{"name":"X","modes":["sepia"]}"##)?.contains("modes") == true)
        #expect(reason(##"{"name":"X","modes":[]}"##)?.contains("modes") == true)
        #expect(reason(##"{"name":"X","light":{"accent":"#336699"}}"##) == nil)
    }

    @Test func conflictsAreFoundAndKeptApart() {
        var copy = EditorTheme.paper
        #expect(ThemeStore.existing(copy)?.id == "paper")
        copy = ThemeStore.keepingBoth(copy)
        #expect(copy.id == "paper-2")
        #expect(copy.name == "Paper 2")
        #expect(ThemeStore.existing(copy) == nil)
    }

    @Test func accentFallsBackToLink() {
        var theme = EditorTheme(id: "t", name: "T", light: .init(link: "#112233"), dark: .init())
        #expect(theme.accentColor != nil)
        theme.light.link = nil
        #expect(theme.accentColor == nil)
    }
}
