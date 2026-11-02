//
//  NamePrompt.swift
//  NmwUI
//
//  Asks for a name (new folder, rename). iOS uses the system alert, which
//  focuses its field; a macOS alert doesn't, so the Mac gets a small sheet
//  whose field has focus and the text selected.
//

import SwiftUI

extension View {
    func namePrompt(_ title: LocalizedStringKey, isPresented: Binding<Bool>, text: Binding<String>, actionTitle: LocalizedStringKey,
                    message: LocalizedStringKey? = nil, onCommit: @escaping () -> Void) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented) {
            NamePromptSheet(title: title, message: message, actionTitle: actionTitle, text: text) {
                onCommit()
                isPresented.wrappedValue = false
            } cancel: {
                isPresented.wrappedValue = false
            }
        }
        #else
        alert(title, isPresented: isPresented) {
            TextField("Name", text: text)
            Button(actionTitle) { onCommit() }
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            if let message { Text(message) }
        }
        #endif
    }
}

#if os(macOS)
private struct NamePromptSheet: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    let actionTitle: LocalizedStringKey
    @Binding var text: String
    let commit: () -> Void
    let cancel: () -> Void
    @FocusState private var focused: Bool

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if let message { Text(message).foregroundStyle(.secondary) }
            TextField("Name", text: $text)
                .focused($focused)
                .onSubmit { if !isEmpty { commit() } }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button(actionTitle, action: commit).keyboardShortcut(.defaultAction).disabled(isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear { focused = true }
    }
}
#endif
