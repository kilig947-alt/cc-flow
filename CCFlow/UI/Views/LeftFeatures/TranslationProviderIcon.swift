import SwiftUI

/// Bundled, original-color service artwork. Fixed bounds keep loading/results
/// from changing row geometry; rendering never requests a favicon over the network.
struct TranslationProviderIcon: View {
    let provider: TranslationProvider
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let assetName = provider.iconAssetName {
                Image(assetName)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
                    .background(.white, in: RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "brain")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension TranslationProvider {
    var iconAssetName: String? {
        self == .ai ? nil : "TranslationBrand-\(rawValue)"
    }
}

extension TranslationOCRProvider {
    var brandProvider: TranslationProvider? {
        switch self {
        case .system: nil
        case .volcano: .volcano
        case .tencent, .tencentImage: .tencent
        case .baidu: .baidu
        case .youdao: .youdao
        case .google: .google
        }
    }
}
