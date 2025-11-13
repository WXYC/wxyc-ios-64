//
//  BreakpointRowView.swift
//  WXYC
//
//  SwiftUI view for Breakpoint playlist entries
//

import SwiftUI
import Core

struct BreakpointRowView: View {
    let breakpoint: Breakpoint

    var body: some View {
        Text(breakpoint.formattedDate)
            .font(.title2)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
