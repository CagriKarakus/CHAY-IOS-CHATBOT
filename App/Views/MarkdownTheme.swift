import MarkdownUI
import SwiftUI

extension MarkdownUI.Theme {
    /// Atom One Dark renkleriyle başlık, liste, tablo ve kod bloğu görünümü.
    @MainActor static let atomOneDark = MarkdownUI.Theme()
        .text {
            ForegroundColor(Palette.text)
            FontSize(16)
        }
        .strong {
            FontWeight(.semibold)
            ForegroundColor(Palette.textBright)
        }
        .emphasis {
            FontStyle(.italic)
        }
        .link {
            ForegroundColor(Palette.blue)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            ForegroundColor(Palette.green)
            BackgroundColor(Palette.surface)
        }
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: 20, bottom: 10)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.5))
                    ForegroundColor(Palette.textBright)
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: 18, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.3))
                    ForegroundColor(Palette.textBright)
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: 16, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.12))
                    ForegroundColor(Palette.textBright)
                }
        }
        .heading4 { configuration in
            configuration.label
                .markdownMargin(top: 14, bottom: 4)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    ForegroundColor(Palette.textBright)
                }
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 0, bottom: 12)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.25))
        }
        .blockquote { configuration in
            configuration.label
                .markdownTextStyle { ForegroundColor(Palette.textMuted) }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Palette.purple)
                        .frame(width: 3)
                }
                .markdownMargin(top: 4, bottom: 12)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.2))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                        ForegroundColor(Palette.text)
                    }
                    .padding(12)
            }
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border, lineWidth: 1))
            .markdownMargin(top: 4, bottom: 12)
        }
        .table { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownTableBorderStyle(.init(color: Palette.border))
                    .markdownTableBackgroundStyle(.alternatingRows(Palette.background, Palette.surface))
            }
            .markdownMargin(top: 4, bottom: 12)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                        ForegroundColor(Palette.textBright)
                    }
                    FontSize(.em(0.92))
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
        }
        .thematicBreak {
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1)
                .markdownMargin(top: 12, bottom: 12)
        }
}
