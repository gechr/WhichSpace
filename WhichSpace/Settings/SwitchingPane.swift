import SwiftUI

/// The Switching settings pane: click and scroll Space switching, scroll
/// behavior, and the accessibility permission both require.
/// Container-agnostic - it knows nothing about the window chrome hosting it.
struct SwitchingPane: View {
    let model: SettingsModel
    /// Plays a haptic sample at the given intensity so slider changes can be
    /// felt while dragging, matching the status menu's slider
    let onHapticPreview: (Int) -> Void

    var body: some View {
        SettingsForm {
            if !model.accessibilityGranted {
                accessibilityBanner
            }
            SettingsSection(Localization.labelClick) {
                SettingsToggleRow(
                    title: Localization.toggleClickToSwitchSpaces,
                    isOn: model.clickToSwitchSpacesBinding,
                    icon: "hand.tap.fill",
                    subtitle: Localization.tipClickToSwitchSpaces,
                    anchor: .clickToSwitch
                )
            }
            scrollSection
            behaviorSection
        }
    }

    /// Shown until accessibility permission is granted; switching cannot
    /// work without it. The button both opens the Accessibility pane and
    /// registers a grant watch so the banner clears live.
    private var accessibilityBanner: some View {
        SettingsSection {
            SettingsRow(anchor: .accessibility) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localization.alertAccessibilityRequired)
                            .fontWeight(.semibold)
                        Text(Localization.bannerAccessibilityDetail)
                            .foregroundStyle(.secondary)
                    }
                }
            } control: {
                Button(Localization.actionOpenSystemSettings) {
                    model.requestAccessibility()
                    Accessibility.openSettingsPane()
                }
            }
        }
    }

    private var scrollSection: some View {
        SettingsSection(Localization.menuScroll) {
            scrollAxisRows(
                Localization.labelVertical,
                axis: \.verticalScrollEnabled,
                invert: \.invertVerticalScroll,
                axisIcon: "arrow.up.and.down",
                invertIcon: "arrow.uturn.up",
                axisAnchor: .verticalScroll,
                invertAnchor: .invertVerticalScroll
            )
            SettingsRowDivider()
            scrollAxisRows(
                Localization.labelHorizontal,
                axis: \.horizontalScrollEnabled,
                invert: \.invertHorizontalScroll,
                axisIcon: "arrow.left.and.right",
                invertIcon: "arrow.uturn.backward",
                axisAnchor: .horizontalScroll,
                invertAnchor: .invertHorizontalScroll
            )
        }
    }

    @ViewBuilder
    private func scrollAxisRows(
        _ title: String,
        axis: ReferenceWritableKeyPath<DefaultsStore, Bool>,
        invert: ReferenceWritableKeyPath<DefaultsStore, Bool>,
        axisIcon: String,
        invertIcon: String,
        axisAnchor: SettingsAnchor,
        invertAnchor: SettingsAnchor
    ) -> some View {
        SettingsToggleRow(
            title: title,
            isOn: model.scrollSwitchingBinding(axis: axis),
            icon: axisIcon,
            subtitle: Localization.tipScrollEnabled,
            anchor: axisAnchor
        )
        SettingsRowDivider()
        SettingsToggleRow(
            title: Localization.toggleScrollInverted,
            isOn: model.binding(invert),
            icon: invertIcon,
            indented: true,
            disabled: !model.value(axis),
            subtitle: Localization.tipScrollInverted,
            anchor: invertAnchor
        )
    }

    private var behaviorSection: some View {
        SettingsSection(Localization.labelBehavior) {
            SettingsToggleRow(
                title: Localization.toggleScrollWrapAround,
                isOn: model.binding(\.scrollWrapAround),
                icon: "repeat",
                subtitle: Localization.tipScrollWrapAround,
                anchor: .scrollWrapAround
            )
            SettingsRowDivider()
            SettingsSliderRow(
                title: Localization.labelSensitivity,
                value: model.binding(\.scrollSensitivity),
                range: Layout.scrollSensitivityRange,
                defaultValue: Layout.defaultScrollSensitivity,
                icon: "speedometer",
                subtitle: Localization.tipSensitivity,
                anchor: .scrollSensitivity
            )
            SettingsRowDivider()
            SettingsSliderRow(
                title: Localization.toggleScrollHapticFeedback,
                value: hapticIntensityBinding,
                range: 0 ... Double(Layout.scrollHapticIntensityRange.upperBound),
                step: 1,
                defaultValue: 0,
                icon: "waveform",
                subtitle: Localization.tipScrollHapticFeedback,
                anchor: .scrollHaptics,
                // The detents read as names rather than numbers
                valueParser: nil
            ) {
                HapticIntensityLabel.label(for: Int($0))
            }
        }
    }

    private var hapticIntensityBinding: Binding<Double> {
        let stored = model.scrollHapticIntensityBinding
        return Binding(
            get: { stored.wrappedValue },
            set: {
                // A drag fires the setter continuously with the same stepped
                // value; preview only when the detent actually changes
                let previous = Int(stored.wrappedValue)
                stored.wrappedValue = $0
                let intensity = Int($0)
                if intensity > 0, intensity != previous {
                    onHapticPreview(intensity)
                }
            }
        )
    }
}
