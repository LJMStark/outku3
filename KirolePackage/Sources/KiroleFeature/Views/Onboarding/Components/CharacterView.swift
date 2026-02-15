import SwiftUI

public struct CharacterView: View {
    let imageName: String
    var size: CGFloat = 80

    @State private var bobOffset: CGFloat = 0

    public init(imageName: String, size: CGFloat = 80) {
        self.imageName = imageName
        self.size = size
    }

    public var body: some View {
        Image(imageName, bundle: .module)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .offset(y: bobOffset)
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    bobOffset = -6
                }
            }
    }
}
