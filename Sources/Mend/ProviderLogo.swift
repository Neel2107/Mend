import AppKit
import SwiftUI

enum ProviderBrand: String {
    case openAI = "OpenAI"
    case gemini = "Gemini"
}

struct ProviderLogo: View {
    let brand: ProviderBrand
    var size: CGFloat = 18
    var tint: Color = .primary

    var body: some View {
        Group {
            if let image = providerImage {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(brand == .openAI ? .template : .original)
                    .foregroundStyle(tint)
            } else {
                Image(systemName: "sparkles")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .clipped()
        .accessibilityHidden(true)
    }

    private var providerImage: NSImage? {
        guard let url = Bundle.main.url(
            forResource: brand.rawValue,
            withExtension: "svg",
            subdirectory: "ProviderIcons"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = brand == .openAI
        return image
    }
}
