import SwiftUI

public struct AvatarSelector: View {
    @Binding var selectedId: AvatarChoice

    public init(selectedId: Binding<AvatarChoice>) {
        self._selectedId = selectedId
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(AvatarChoice.allCases, id: \.self) { avatar in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedId = avatar
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Image(avatar.imageName, bundle: .module)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay {
                                    if selectedId == avatar {
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(.white, lineWidth: 4)
                                    }
                                }
                                .opacity(selectedId == avatar ? 1.0 : 0.7)
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                            Text(avatar.displayName)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
