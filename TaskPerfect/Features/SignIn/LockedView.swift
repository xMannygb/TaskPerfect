import SwiftUI

/// Shown while the app is locked behind biometrics.
///
/// It has its own screen rather than presenting the prompt over the task list,
/// because the list would be readable underneath while the sheet was up — which
/// defeats the point of locking it.
struct LockedView: View {

    @Environment(Session.self) private var session: Session?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            AppMark(size: 56)
                .padding(.bottom, 20)

            Text("Task Perfect")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)

            Text("Locked")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.slate)
                .padding(.top, 4)

            Button {
                Task { await session?.authenticate() }
            } label: {
                Label("Unlock with \(AppLock.biometryName)", systemImage: lockSymbol)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Palette.ink)
            .padding(.horizontal, 40)
            .padding(.top, 28)

            Spacer()

            Button("Use password instead") {
                session?.signOut()
            }
            .font(.subheadline)
            .foregroundStyle(Theme.Palette.slate)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.canvas)
        // Prompt straight away, so the common case is one glance and in.
        .task { await session?.authenticate() }
    }

    private var lockSymbol: String {
        switch AppLock.biometryName {
        case "Face ID":  return "faceid"
        case "Touch ID": return "touchid"
        default:         return "lock.open"
        }
    }
}

#Preview {
    LockedView()
}
