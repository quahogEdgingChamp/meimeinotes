import SwiftUI

struct CatPortraitView: View {
    let portrait: CatPortrait

    var body: some View {
        Image(nsImage: portrait.image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: portrait.isCutout ? 0 : 12))
    }
}
