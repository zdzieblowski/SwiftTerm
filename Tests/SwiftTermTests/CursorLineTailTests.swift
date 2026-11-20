//
//  CursorLineTailTests.swift
//
//  The cursor's line isn't reflowed on resize (the program redraws it), so a
//  narrowing cuts its end off. That end is kept and put back when the
//  terminal widens again, as long as nothing changed the line meanwhile: a
//  prompt that nothing redraws (ssh's password prompt) isn't lost.
//
import Foundation
import Testing

@testable import SwiftTerm

final class CursorLineTailTests {
    private func make(cols: Int, rows: Int = 6) -> Terminal {
        TerminalTestHarness.makeTerminal(cols: cols, rows: rows, scrollback: 100).terminal
    }

    private func text(_ terminal: Terminal, _ row: Int) -> String {
        TerminalTestHarness.lineText(buffer: terminal.buffer, row: row) ?? ""
    }

    @Test func narrowingThenWideningPutsThePromptBack() {
        let t = make(cols: 80)
        t.feed(text: "first\r\nuser@example.com's password: ")
        t.resize(cols: 25, rows: 6)
        #expect(text(t, 1) == "user@example.com's passwo")
        t.resize(cols: 12, rows: 6)
        t.resize(cols: 80, rows: 6)
        #expect(text(t, 1) == "user@example.com's password: ")
        TerminalTestHarness.assertCursor(t.buffer, col: 29, row: 1)
        t.feed(text: "x")
        #expect(text(t, 1) == "user@example.com's password: x")
    }

    @Test func wideningPartlyPutsBackWhatFits() {
        let t = make(cols: 80)
        t.feed(text: "user@example.com's password: ")
        t.resize(cols: 12, rows: 6)
        t.resize(cols: 20, rows: 6)
        #expect(text(t, 0) == "user@example.com's p")
        t.resize(cols: 80, rows: 6)
        #expect(text(t, 0) == "user@example.com's password: ")
        TerminalTestHarness.assertCursor(t.buffer, col: 29, row: 0)
    }

    @Test func aLineRedrawnAfterTheResizeIsLeftAlone() {
        let t = make(cols: 40)
        t.feed(text: "out\r\n$ echo the quick brown fox")
        t.resize(cols: 20, rows: 6)
        // A shell's redraw: back to the start, clear, write the line again.
        t.feed(text: "\r\u{1b}[K$ echo the quick bro\r\nwn fox")
        t.resize(cols: 40, rows: 6)
        #expect(text(t, 1) == "$ echo the quick bro")
        #expect(text(t, 2) == "wn fox")
    }

    @Test func aChangedLineIsLeftAlone() {
        let t = make(cols: 40)
        t.feed(text: "user@example.com's password: ")
        t.resize(cols: 12, rows: 6)
        t.feed(text: "\r\u{1b}[KPassword:")
        t.resize(cols: 40, rows: 6)
        #expect(text(t, 0) == "Password:")
    }

    @Test func textBelowTheCursorIsKept() {
        let t = make(cols: 30)
        t.feed(text: "first\r\nPROMPT abcdefghijklm\r\nbelow1\r\nbelow2\r\nbelow3\r\nbelow4\u{1b}[4A\u{1b}[21G")
        t.resize(cols: 10, rows: 6)
        t.resize(cols: 30, rows: 6)
        #expect(text(t, 1) == "PROMPT abcdefghijklm")
        #expect((2...5).map { text(t, $0) } == ["below1", "below2", "below3", "below4"])
    }

    // Anything written to the cut line after the narrowing drops what was
    // kept, even when the line reads the same afterwards.

    @Test func theSameTextWrittenAgainIsLeftAlone() {
        let t = make(cols: 40)
        t.feed(text: "user@example.com's password: ")
        t.resize(cols: 12, rows: 6)
        // A program redrawing its line the same way, cursor back where it was.
        t.feed(text: "\ruser@example")
        t.resize(cols: 40, rows: 6)
        #expect(text(t, 0) == "user@example")
    }

    @Test func anEraseIsLeftAlone() {
        let t = make(cols: 80)
        t.feed(text: "$ \u{1b}[70GRIGHT-SIDE\u{1b}[1;3H")
        t.resize(cols: 40, rows: 6)
        t.feed(text: "\u{1b}[K")
        t.resize(cols: 100, rows: 6)
        #expect(text(t, 0) == "$ ")
    }

    @Test func aColourChangeIsLeftAlone() {
        let t = make(cols: 40)
        t.feed(text: "user@example.com's password: ")
        t.resize(cols: 10, rows: 6)
        t.feed(text: "\r\u{1b}[31muser@examp\u{1b}[0m")
        t.resize(cols: 40, rows: 6)
        #expect(text(t, 0) == "user@examp")
    }

    @Test func aRecycledLineGetsNothing() {
        let t = TerminalTestHarness.makeTerminal(cols: 20, rows: 3, scrollback: 0).terminal
        t.feed(text: "abcdefghij")
        t.resize(cols: 5, rows: 3)
        t.feed(text: "\n\n\n\rabcde")
        t.resize(cols: 20, rows: 3)
        #expect((0..<3).map { text(t, $0) }.allSatisfy { !$0.contains("fghij") })
    }

    @Test func aContinuationRowBelowIsLeftAlone() {
        let t = make(cols: 40)
        t.feed(text: "out\r\n$ echo the quick brown fox\u{1b}[6G")
        t.resize(cols: 20, rows: 6)
        // zsh's redraw: the line again, wrapped, cursor back on its first row.
        t.feed(text: "\r\u{1b}[J$ echo the quick brown fox\u{1b}[A\u{1b}[6G")
        t.resize(cols: 40, rows: 6)
        #expect(text(t, 1) == "$ echo the quick bro")
        #expect(text(t, 2) == "wn fox")
    }

    /// The end cut off before the write doesn't come back; what the line
    /// held after it (as shown at 25 columns) does.
    @Test func narrowingAgainAfterAWriteKeepsOnlyTheNewLine() {
        let t = make(cols: 80)
        t.feed(text: "user@example.com's password: ")
        t.resize(cols: 25, rows: 6)
        t.feed(text: "\u{1b}[15GXXXXX\u{1b}[25G")
        t.resize(cols: 12, rows: 6)
        t.resize(cols: 80, rows: 6)
        #expect(text(t, 0) == "user@example.cXXXXXpasswo")
    }

    @Test func aCursorMovedAwayAndBackIsLeftAlone() {
        let t = make(cols: 80)
        t.feed(text: "user@example.com's password: ")
        t.resize(cols: 25, rows: 6)
        // At the last column with a wrap pending, then moved off and back:
        // the same column, but no wrap pending.
        t.feed(text: "\u{1b}[D\u{1b}[C")
        t.resize(cols: 80, rows: 6)
        #expect(text(t, 0) == "user@example.com's passwo")
        TerminalTestHarness.assertCursor(t.buffer, col: 24, row: 0)
    }

    @Test func aWideCharacterAtTheCutComesBackWhole() {
        let t = make(cols: 40)
        t.feed(text: "abcd中文efgh")
        t.resize(cols: 5, rows: 6)
        t.resize(cols: 40, rows: 6)
        #expect(text(t, 0) == "abcd中文efgh")
        TerminalTestHarness.assertCursor(t.buffer, col: 12, row: 0)
    }

    @Test func theSavedCursorComesBackWithTheLine() {
        let t = make(cols: 40)
        t.feed(text: "user@example.com's password: \u{1b}7")
        t.resize(cols: 12, rows: 6)
        t.resize(cols: 40, rows: 6)
        t.feed(text: "\u{1b}8X")
        #expect(text(t, 0) == "user@example.com's password: X")
    }

    @Test func clearingDropsWhatWasKept() {
        let t = make(cols: 80)
        t.feed(text: "\u{1b}[50Gtail-text\r")
        t.resize(cols: 20, rows: 6)
        t.feed(text: "\u{1b}[2J\u{1b}[H")
        t.resize(cols: 80, rows: 6)
        #expect(text(t, 0) == "")
    }
}
