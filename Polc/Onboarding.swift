//
//  Onboarding.swift
//  Polc
//
//  Created by Alin Panaitiu on 07.12.2023.
//

import Defaults
import Foundation
import Lowtech
import SwiftUI

struct DropZoneDemoAnimationView: View {
    @Binding var dropped: Bool

    @Default(.floatingResultsCorner) var floatingResultsCorner

    var dropZonePlace: String {
        switch floatingResultsCorner {
        case .bottomLeft: "bottom left corner"
        case .bottomRight: "bottom right corner"
        case .topLeft: "top left corner"
        case .topRight: "top right corner"
        case .top: "top edge"
        case .bottom: "bottom edge"
        case .left: "left edge"
        case .right: "right edge"
        case .center: "centre"
        }
    }

    var image: some View {
        VStack(spacing: Space.s) {
            SwiftUI.Image(nsImage: NSImage(resource: .sonomaShot))
                .resizable()
                .background(
                    Rectangle()
                        .fill(Color.white)
                        .scaleEffect(x: 1.15, y: 1.2)
                        .themeShadow(.raised)
                )
                .scaledToFill()
                .frame(width: 70, height: 50)
            Text("screenshot.png")
                .font(.round(TextSize.callout))
                .foregroundColor(clicked ? .white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(Color.blue.opacity(clicked ? 1.0 : 0.0))
                        .scaleEffect(1.1)
                )
        }
    }
    var imageFileWithCursor: some View {
        ZStack {
            image
                .scaleEffect(letGo ? 0.0 : (clicked ? 1.05 : 1.0))
            SwiftUI.Image(systemName: clicked ? "cursorarrow.rays" : "cursorarrow")
                .foregroundColor(.black)
                .font(.system(size: clicked ? 32 : 24, weight: .bold))
                .offset(x: 10, y: 0)
        }
    }
    var body: some View {
        VStack {
            HStack(spacing: Self.demoGap) {
                ZStack {
                    image.offset(Self.INITIAL_OFFSET)
                    imageFileWithCursor.offset(draggedFileOffset)
                }
                DropZoneView().padding(.horizontal, -20)
            }
            Text("Drag files into the **drop zone** at\nthe **\(dropZonePlace)** of your screen")
                .multilineTextAlignment(.center)
        }
        .onAppear {
            mainAsyncAfter(ms: 1000) {
                withAnimation(.snappy(duration: 0.2)) {
                    clicked = true
                }
                mainAsyncAfter(ms: 300) {
                    withAnimation(.smooth(duration: 0.7)) {
                        draggedFileOffset = CGSize(width: 310, height: 10)
                    }
                }
                mainAsyncAfter(ms: 700) {
                    withAnimation(.jumpySpring) {
                        dragManager.dragHovering = true
                    }
                }
                mainAsyncAfter(ms: 1300) {
                    withAnimation(.smooth(duration: 0.2)) {
                        letGo = true
                        clicked = false
                    }
                }
                mainAsyncAfter(ms: 2000) {
                    withAnimation(.easeOut) {
                        dropped = true
                        dragManager.dragHovering = false
                    }
                }
            }
        }
    }

    private static var INITIAL_OFFSET = CGSize(width: 0, height: -30)
    private static let demoGap: CGFloat = 100

    @State private var draggedFileOffset = INITIAL_OFFSET
    @State private var clicked = false
    @State private var letGo = false
    @ObservedObject private var dragManager = DM

}
struct OnboardingView: View {
    @ObservedObject var bm = BM

    @Default(.enableAutomaticImageOptimisations) var enableAutomaticImageOptimisations
    @Default(.enableAutomaticVideoOptimisations) var enableAutomaticVideoOptimisations
    @Default(.enableAutomaticPDFOptimisations) var enableAutomaticPDFOptimisations
    @Default(.enableAutomaticAudioOptimisations) var enableAutomaticAudioOptimisations

    var polcLogo: some View {
        ZStack(alignment: .topLeading) {
            Text("Polc")
                .font(.round(TextSize.wordmark, weight: .black))
            SwiftUI.Image("polc")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .offset(x: -10, y: -22)
                .rotationEffect(.degrees(-15))
        }
    }

    var menubar: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                .frame(height: 24)
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Color.primary.opacity(0.1))
                .frame(height: 24)
            HStack(spacing: Space.m) {
                SwiftUI.Image(nsImage: NSImage(resource: menubarIconResource(classic: useClassicMenubarIcon, geometric: useGeometricMenubarIcon)))
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 21, height: 21)
                SwiftUI.Image(systemName: "wifi")
                Text("10:09")
            }
            .font(.regular(TextSize.title3))
            .padding(.trailing, Space.s)
        }
        .mask(LinearGradient(gradient: Gradient(colors: [.clear, .white]), startPoint: .leading, endPoint: .trailing))
    }

    var body: some View {
        ZStack {
            VStack {
                HStack {
                    polcLogo.padding()
                    VStack(alignment: .trailing) {
                        if showMenubarIcon {
                            menubar
                            Text("""
                            Polc lives in your **menubar** and waits for you
                            to copy an image or **screenshot to clipboard**.
                            Copied **video**, **audio** and **PDF** files can be
                            optimised too, in **Settings → Clipboard**.
                            """)
                            .font(.round(TextSize.body, weight: .regular))
                        } else {
                            Text("""
                            Polc runs in the **background** and waits for you
                            to copy an image or **screenshot to clipboard**.
                            Its menubar icon is hidden: **open Polc again** from
                            Finder or Spotlight to get to **Settings**.
                            Copied **video**, **audio** and **PDF** files can be
                            optimised too, in **Settings → Clipboard**.
                            """)
                            .font(.round(TextSize.body, weight: .regular))
                        }
                        Toggle(" Enable clipboard optimiser", isOn: $enableClipboardOptimiser)
                            .font(.round(TextSize.subheadline, weight: .regular))
                            .controlSize(.mini)
                    }
                }
                ZStack {
                    Color.bg.warm
                        .border(Color.black.opacity(colorScheme == .dark ? 0.4 : 0.1))
                        .scaleEffect(x: 1.3, y: 1.15)
                        .offset(y: 5)

                    if fileDropped {
                        VStack {
                            HStack {
                                OnboardingFloatingPreview()
                                    .offset(x: -40, y: 0)
                                Text("""
                                Optimised images will appear
                                as **floating thumbnails** in
                                the **corner of your screen**,
                                so you can further act on them.
                                """)
                            }
                            Button("Replay") {
                                fileDropped = false
                            }
                        }
                        .frame(width: 530, height: 200)
                    } else {
                        DropZoneDemoAnimationView(dropped: $fileDropped)
                            .frame(width: 530, height: 200)
                    }
                }
                .padding(.bottom, Space.xl)

                Text("""
                Polc can also watch folders for new **images**, **videos**,
                **PDFs** and **audio** files and **automatically** optimise them.
                """)
                .font(.round(TextSize.body, weight: .regular))
                .padding()
                .multilineTextAlignment(.center)
                VStack {
                    HStack {
                        VStack {
                            Text("Images").round(TextSize.callout)
                            DirListView(fileType: .image, dirs: $imageDirs, enabled: $enableAutomaticImageOptimisations, hideIgnoreRules: true)
                        }
                        VStack {
                            Text("Videos").round(TextSize.callout)
                            DirListView(fileType: .video, dirs: $videoDirs, enabled: $enableAutomaticVideoOptimisations, hideIgnoreRules: true)
                        }
                    }
                    HStack {
                        VStack {
                            Text("PDFs").round(TextSize.callout)
                            DirListView(fileType: .pdf, dirs: $pdfDirs, enabled: $enableAutomaticPDFOptimisations, hideIgnoreRules: true)
                        }
                        VStack {
                            Text("Audio").round(TextSize.callout)
                            DirListView(fileType: .audio, dirs: $audioDirs, enabled: $enableAutomaticAudioOptimisations, hideIgnoreRules: true)
                        }
                    }
                }
                .padding(.bottom, Space.xl)

                if bm.decompressingBinaries {
                    ProgressView("Preparing optimisers...")
                        .progressViewStyle(.linear)
                        .padding()
                } else {
                    Button("Start using Polc") {
                        (AppDelegate.instance as? AppDelegate)?.onboardingWindowController?.close()
                    }
                    .font(.round(TextSize.body, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.9))
                }
            }
            .padding()
            .blur(radius: min(0.6 - maskOpacity, 0.6) * 8)
            .mask(LinearGradient(stops: [
                .init(color: .white, location: maskOpacity + 0.1),
                .init(color: .clear, location: maskOpacity + 0.2),
            ], startPoint: .top, endPoint: .bottom))
            LinearGradient(
                gradient: Gradient(
                    colors: [.bg.warm.opacity(min(0.3 - maskOpacity, 0.3)), .bg.warm.opacity(1 - maskOpacity)]
                ),
                startPoint: .init(x: 0, y: -1),
                endPoint: .center
            )
            .scaleEffect(1.5)
            .allowsHitTesting(false)
        }
        .fixedSize()
        .focusable(false)
        .onAppear {
            withAnimation(.linear(duration: 2.5)) {
                maskOpacity = 1
            }
            mainAsyncAfter(ms: 5000) {
                fileDropped = false
            }
        }
    }

    @State private var fileDropped = true

    @State private var maskOpacity = 0.0

    @Environment(\.colorScheme) private var colorScheme

    @Default(.enableClipboardOptimiser) private var enableClipboardOptimiser
    @Default(.imageDirs) private var imageDirs
    @Default(.videoDirs) private var videoDirs
    @Default(.pdfDirs) private var pdfDirs
    @Default(.audioDirs) private var audioDirs
    @Default(.showMenubarIcon) private var showMenubarIcon
    @Default(.useClassicMenubarIcon) private var useClassicMenubarIcon
    @Default(.useGeometricMenubarIcon) private var useGeometricMenubarIcon
}

#Preview {
    OnboardingView()
}
