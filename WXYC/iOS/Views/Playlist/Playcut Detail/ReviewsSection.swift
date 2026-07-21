//
//  ReviewsSection.swift
//  WXYC
//
//  Attributed external critic-review snippets for a playcut's album (ADR 0012).
//  One card per review — source + date, the snippet as a pull quote, and a
//  mandatory link-out to the original review. Mirrors the structure and styling
//  of the sibling ExternalLinksSection / StreamingLinksSection cards.
//
//  Created by Jake Bromberg on 07/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import UIKit
import Metadata
import WXUI

struct ReviewsSection: View {
    let reviews: [CriticReview]
    var onLinkTapped: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reviews")
                .font(.detailSectionHeader)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(reviews, id: \.url) { review in
                ReviewCard(review: review, onLinkTapped: onLinkTapped)
            }
        }
        .tint(.primary)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.primary.opacity(0.1))
        )
    }
}

// MARK: - Review Card

private struct ReviewCard: View {
    let review: CriticReview
    var onLinkTapped: ((String) -> Void)?

    /// "The Quietus · 2024-03-15" when a date is present, else just the source.
    private var attribution: String {
        if let date = review.publishedDate, !date.isEmpty {
            return "\(review.source) · \(date)"
        }
        return review.source
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(attribution)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if let rating = review.rating, !rating.isEmpty {
                    Text(rating)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }
            }

            Text(review.snippet)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let author = review.author, !author.isEmpty {
                Text("— \(author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                onLinkTapped?(review.source)
                UIApplication.shared.open(review.url)
            } label: {
                LinkButtonLabel(
                    icon: .system(name: "arrow.up.right"),
                    title: "Read on \(review.source)",
                    font: .subheadline,
                    foregroundShapeStyle: AnyShapeStyle(.primary),
                    backgroundFill: AnyShapeStyle(.primary.opacity(0.15)),
                    alignment: .center,
                    spacing: 12
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.primary.opacity(0.06))
        )
    }
}

// MARK: - Preview

#Preview {
    ReviewsSection(
        reviews: [
            CriticReview(
                source: "The Quietus",
                url: URL(string: "https://thequietus.com/articles/juana-molina-doga")!,
                snippet: "Juana Molina folds field recordings and looped guitar into songs that keep dissolving and re-forming, restless and quietly radical.",
                author: "Jane Critic",
                publishedDate: "2024-03-15",
                rating: "8.0"
            ),
            CriticReview(
                source: "The Quietus",
                url: URL(string: "https://thequietus.com/articles/second")!,
                snippet: "A short, attributed pull quote with only the fields the corpus reliably carries."
            )
        ]
    )
    .padding()
    .foregroundStyle(.white)
    .background(.black)
}
