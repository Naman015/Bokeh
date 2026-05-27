import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection

                VStack(spacing: 16) {
                    policySection(
                        title: "Data Collection",
                        body: "Bokeh does not collect, transmit, or share any personal data. There are no analytics, telemetry, advertising, or tracking of any kind. The app makes zero network requests."
                    )

                    policySection(
                        title: "Camera Usage",
                        body: "Bokeh uses your device camera to identify and isolate objects using Apple's on-device Vision framework. Camera frames are processed in real-time and are never recorded, stored, or transmitted. Only the isolated object cutout is saved when you choose to log it."
                    )

                    policySection(
                        title: "On-Device Storage",
                        body: "When you clear an item, the following is stored locally on your device: the item label, an optional location tag, a cutout image, a timestamp, and the duration it took to clear. This data is indexed in Core Spotlight so you can search for items from your home screen. All data remains on your device."
                    )

                    policySection(
                        title: "Third-Party Services",
                        body: "Bokeh uses zero third-party SDKs, frameworks, analytics services, crash reporters, or advertising networks. All intelligence is provided by Apple's built-in Vision and Natural Language frameworks running entirely on your device."
                    )

                    policySection(
                        title: "Data Retention & Deletion",
                        body: "Your data is stored until you choose to delete it. You can delete individual items from the Focus Log detail view, or use \"Clear All\" to remove everything at once. Deletion also removes the corresponding Spotlight search index entries."
                    )

                    policySection(
                        title: "Children's Privacy",
                        body: "Bokeh does not knowingly collect personal information from children. Since the app collects no personal data from any user, no special provisions are required."
                    )

                    policySection(
                        title: "Changes to This Policy",
                        body: "If this privacy policy changes, updates will be reflected in a future app update. The effective date at the top of this page will be updated accordingly."
                    )

                    policySection(
                        title: "Contact",
                        body: "If you have questions about this privacy policy, contact the developer at namanbmwork@gmail.com."
                    )
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 20)
                .padding(.bottom, 32)
            }
        }
        .background(Color.theme.bokehSand.ignoresSafeArea())
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.theme.bokehTeal)
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            BokehLogoView(size: 60)

            Text("Privacy Policy")
                .bokehFont(.title2, weight: .bold)
                .foregroundStyle(Color.theme.bokehTitleColor)

            Text("Effective May 2026")
                .bokehFont(.caption, weight: .medium)
                .foregroundStyle(Color.theme.bokehCaption)
        }
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private func policySection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .bokehFont(.headline, weight: .semibold)
                .foregroundStyle(Color.theme.bokehTitleColor)
            Text(body)
                .bokehFont(.subheadline, weight: .regular)
                .foregroundStyle(Color.theme.bokehBodyColor)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
