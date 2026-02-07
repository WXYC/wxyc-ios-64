//
//  PhotoPickerCard.swift
//  Wallpaper
//
//  Special carousel card for photo background selection. Shows a placeholder when no
//  photo is set, or the selected photo preview when one exists. Carousel navigation is
//  handled by ThemeCarouselView; a button overlaid below the card opens the picker.
//
//  Created by Claude on 01/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Logger
import SwiftUI

#if os(iOS)
import PhotosUI
import UIKit
#endif

/// A card view for selecting a photo background in the theme carousel.
///
/// When no photo is set, displays a placeholder with an icon.
/// When a photo exists, shows the photo preview. Carousel navigation taps are
/// handled externally by `ThemeCarouselView`. A button overlaid below the card
/// opens `PhotosPicker` for photo selection.
struct PhotoPickerCard: View {
    /// The photo storage service.
    let storage: PhotoBackgroundStorageProtocol

    /// The card size.
    let cardSize: CGSize

    /// The corner radius.
    let cornerRadius: CGFloat

    /// Callback when a photo is successfully saved.
    var onPhotoSaved: (() -> Void)?

    /// Whether the picker is shown.
    @State private var isPickerPresented = false

    #if os(iOS)
    /// The selected photo item from PhotosPicker.
    @State private var selectedItem: PhotosPickerItem?
    #endif

    /// The loaded preview image.
    @State private var previewImage: Core.Image?

    /// Whether a photo is currently being loaded.
    @State private var isLoading = false

    /// Space reserved above the card for the label.
    private let labelHeight: CGFloat = 40

    var body: some View {
        cardContent
            .frame(width: cardSize.width, height: cardSize.height)
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .overlay(alignment: .top) {
                Text("Photo")
                    .font(.headline)
                    .bold()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                    .offset(y: -labelHeight)
            }
            // Limit the card's hit-testing area so the outer onTapGesture
            // (added by ThemeCarouselView) does not intercept button taps.
            .contentShape(.rect)
            .overlay(alignment: .bottom) {
                // Picker button below the card, tracking it on scroll
                Button(
                    previewImage != nil ? "Change Photo" : "Choose Photo",
                    systemImage: "photo.on.rectangle.angled"
                ) {
                    isPickerPresented = true
                }
                .font(.subheadline)
                .bold()
                .foregroundStyle(.white.opacity(0.8))
                .buttonStyle(.plain)
                .offset(y: 48)
            }
            #if os(iOS)
            .photosPicker(
                isPresented: $isPickerPresented,
                selection: $selectedItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await loadAndSavePhoto(from: newItem)
                }
            }
            #endif
            .task {
                await loadPreview()
            }
    }

    @ViewBuilder
    private var cardContent: some View {
        ZStack {
            if let image = previewImage {
                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                #elseif os(macOS)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                #endif
            } else {
                // Placeholder when no photo is set
                LinearGradient(
                    colors: [
                        Color(white: 0.15),
                        Color(white: 0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }

    /// Loads the preview image from storage.
    @MainActor
    private func loadPreview() async {
        guard storage.hasPhoto else { return }
        previewImage = await storage.loadPhoto()
    }

    #if os(iOS)
    /// Loads a photo from the PhotosPickerItem and saves it to storage.
    @MainActor
    private func loadAndSavePhoto(from item: PhotosPickerItem) async {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                Log(.error, "PhotosPickerItem returned nil data")
                return
            }

            guard let image = UIImage(data: data) else {
                Log(.error, "Failed to create UIImage from photo data (\(data.count) bytes)")
                return
            }

            try await storage.savePhoto(image, maxDimension: nil)

            // Show the original image immediately rather than round-tripping
            // through storage encoding/decoding.
            previewImage = image
            onPhotoSaved?()
        } catch {
            Log(.error, "Failed to save photo: \(error)")
        }
    }
    #endif
}

// MARK: - Preview

#if DEBUG
#Preview("Photo Picker Card - Empty") {
    ZStack {
        Color.black
        PhotoPickerCard(
            storage: PreviewEmptyPhotoStorage(),
            cardSize: CGSize(width: 300, height: 500),
            cornerRadius: 40
        )
    }
}

#Preview("Photo Picker Card - With Photo") {
    ZStack {
        Color.black
        PhotoPickerCard(
            storage: PreviewPhotoStorageWithImage(),
            cardSize: CGSize(width: 300, height: 500),
            cornerRadius: 40
        )
    }
}

@MainActor
private final class PreviewEmptyPhotoStorage: PhotoBackgroundStorageProtocol {
    var hasPhoto: Bool { false }
    var metadata: PhotoBackgroundMetadata? { nil }
    func loadPhoto() async -> Core.Image? { nil }
    func savePhoto(_ image: Core.Image, maxDimension: CGFloat?) async throws {}
    func deletePhoto() throws {}
}

@MainActor
private final class PreviewPhotoStorageWithImage: PhotoBackgroundStorageProtocol {
    var hasPhoto: Bool { true }
    var metadata: PhotoBackgroundMetadata? {
        PhotoBackgroundMetadata(accentHue: 210, accentSaturation: 0.7, accentBrightness: 1.0)
    }
    func loadPhoto() async -> Core.Image? {
        #if os(iOS)
        UIImage(systemName: "photo.fill")
        #else
        nil
        #endif
    }
    func savePhoto(_ image: Core.Image, maxDimension: CGFloat?) async throws {}
    func deletePhoto() throws {}
}
#endif
