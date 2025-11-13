//
//  TalksetRowView.swift
//  WXYC
//
//  SwiftUI view for Talkset playlist entries
//

import SwiftUI
import Core

struct TalksetRowView: View {
    let talkset: Talkset

    var body: some View {
        Text("Talkset")
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
