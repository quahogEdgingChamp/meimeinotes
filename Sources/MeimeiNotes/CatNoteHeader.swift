import SwiftUI

struct CatNoteHeader: View {
    let portrait: CatPortrait
    let palette: Palette

    var body: some View {
        GeometryReader { geometry in
            let width = max(0, min(320, geometry.size.width - 28))
            let bottomInset: CGFloat = portrait.isFramed ? 10 : 1
            let height = max(0, geometry.size.height - 10 - bottomInset)
            let photoShape = RoundedRectangle(cornerRadius: portrait.isFramed ? 12 : 0)

            ZStack(alignment: .bottom) {
                LinearGradient(colors: [palette.portraitBackdrop, palette.paper], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [palette.portraitHighlight, .clear], center: .init(x: 0.5, y: 0.26),
                               startRadius: 8, endRadius: 180)

                Rectangle()
                    .fill(palette.border)
                    .frame(height: 1)
                    .padding(.horizontal, 12)

                Image(nsImage: portrait.image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .background(portrait.isFramed ? palette.portraitMat : .clear)
                    .clipShape(photoShape)
                    .overlay {
                        if portrait.isFramed { photoShape.strokeBorder(palette.border) }
                    }
                    .frame(width: width, height: height, alignment: .bottom)
                    .shadow(color: .black.opacity(0.16), radius: 5, y: 3)
                    .padding(.bottom, bottomInset)
            }
        }
    }
}
