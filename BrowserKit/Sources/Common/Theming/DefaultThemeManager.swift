// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit

typealias KeyedPrivateModeFlags = [String: NSNumber]

/// The `ThemeManager` will be responsible for providing the theme throughout the app
public final class DefaultThemeManager: ThemeManager, Notifiable {
    // These have been carried over from the legacy system to maintain backwards compatibility
    enum ThemeKeys {
        static let themeName = "prefKeyThemeName"
        static let systemThemeIsOn = "prefKeySystemThemeSwitchOnOff"

        enum AutomaticBrightness {
            static let isOn = "prefKeyAutomaticSwitchOnOff"
            static let thresholdValue = "prefKeyAutomaticSliderValue"
        }

        enum NightMode {
            static let isOn = "profile.NightModeStatus"
        }

        enum PrivateMode {
            static let byWindowUUID = "profile.PrivateModeWindowStatusByWindowUUID"

            static let legacy_isOn = "profile.PrivateModeStatus"
        }
    }

    // MARK: - Variables

    private var windowThemeState: [UUID: Theme] = [:]
    private var windows: [UUID: UIWindow] = [:]
    private var allWindowUUIDs: [UUID] { return Array(windows.keys) }
    public var notificationCenter: NotificationProtocol

    private var userDefaults: UserDefaultsInterface
    private var mainQueue: DispatchQueueInterface
    private var sharedContainerIdentifier: String

    private var nightModeIsOn: Bool {
        return userDefaults.bool(forKey: ThemeKeys.NightMode.isOn)
    }

    private func privateModeIsOn(for window: UUID) -> Bool {
        return getPrivateThemeIsOn(for: window)
    }

    public var systemThemeIsOn: Bool {
        return userDefaults.bool(forKey: ThemeKeys.systemThemeIsOn)
    }

    public var automaticBrightnessIsOn: Bool {
        return userDefaults.bool(forKey: ThemeKeys.AutomaticBrightness.isOn)
    }

    public var automaticBrightnessValue: Float {
        return userDefaults.float(forKey: ThemeKeys.AutomaticBrightness.thresholdValue)
    }

    // MARK: - Initializers

    public init(
        userDefaults: UserDefaultsInterface = UserDefaults.standard,
        notificationCenter: NotificationProtocol = NotificationCenter.default,
        mainQueue: DispatchQueueInterface = DispatchQueue.main,
        sharedContainerIdentifier: String
    ) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
        self.mainQueue = mainQueue
        self.sharedContainerIdentifier = sharedContainerIdentifier

        self.userDefaults.register(defaults: [
            ThemeKeys.systemThemeIsOn: true,
            ThemeKeys.NightMode.isOn: false
        ])

        setupNotifications(forObserver: self,
                           observing: [UIScreen.brightnessDidChangeNotification,
                                       UIApplication.didBecomeActiveNotification])
    }

    // MARK: - ThemeManager

    public func windowNonspecificTheme() -> Theme {
        switch getNormalSavedTheme() {
        case .dark, .privateMode: return DarkTheme()
        case .light: return LightTheme()
        }
    }

    public func windowDidClose(uuid: UUID) {
        windows.removeValue(forKey: uuid)
        windowThemeState.removeValue(forKey: uuid)
    }

    public func setWindow(_ window: UIWindow, for uuid: UUID) {
        windows[uuid] = window
        updateSavedTheme(to: getNormalSavedTheme())
        updateCurrentTheme(to: fetchSavedThemeType(for: uuid), for: uuid)
    }

    public func currentTheme(for window: UUID?) -> Theme {
        guard let window else {
            assertionFailure("Attempt to get the theme for a nil window UUID.")
            return DarkTheme()
        }

        return windowThemeState[window] ?? DarkTheme()
    }

    public func changeCurrentTheme(_ newTheme: ThemeType, for window: UUID) {
        guard currentTheme(for: window).type != newTheme else { return }

        updateSavedTheme(to: newTheme)
        updateCurrentTheme(to: fetchSavedThemeType(for: window), for: window)
    }

    public func reloadTheme(for window: UUID) {
        updateCurrentTheme(to: fetchSavedThemeType(for: window), for: window)
    }

    public func systemThemeChanged() {
        allWindowUUIDs.forEach { uuid in
            // Ignore if:
            // the system theme is off
            // OR night mode is on
            // OR private mode is on
            guard systemThemeIsOn,
                  !nightModeIsOn,
                  !privateModeIsOn(for: uuid)
            else { return }

            changeCurrentTheme(getSystemThemeType(), for: uuid)
        }
    }

    public func setSystemTheme(isOn: Bool) {
        userDefaults.set(isOn, forKey: ThemeKeys.systemThemeIsOn)

        if isOn {
            systemThemeChanged()
        } else if automaticBrightnessIsOn {
            updateThemeBasedOnBrightness()
        }
    }

    public func setPrivateTheme(isOn: Bool, for window: UUID) {
        let currentSetting = getPrivateThemeIsOn(for: window)
        guard currentSetting != isOn else { return }

        var settings: KeyedPrivateModeFlags
        = userDefaults.object(forKey: ThemeKeys.PrivateMode.byWindowUUID) as? KeyedPrivateModeFlags ?? [:]

        settings[window.uuidString] = NSNumber(value: isOn)
        userDefaults.set(settings, forKey: ThemeKeys.PrivateMode.byWindowUUID)

        updateCurrentTheme(to: fetchSavedThemeType(for: window), for: window)
    }

    public func getPrivateThemeIsOn(for window: UUID) -> Bool {
        let settings = userDefaults.object(forKey: ThemeKeys.PrivateMode.byWindowUUID) as? KeyedPrivateModeFlags
        if settings == nil {
            migrateSingleWindowPrivateDefaultsToMultiWindow(for: window)
        }

        let boxedBool = settings?[window.uuidString] as? NSNumber
        return boxedBool?.boolValue ?? false
    }

    public func setAutomaticBrightness(isOn: Bool) {
        guard automaticBrightnessIsOn != isOn else { return }

        userDefaults.set(isOn, forKey: ThemeKeys.AutomaticBrightness.isOn)
        brightnessChanged()
    }

    public func setAutomaticBrightnessValue(_ value: Float) {
        userDefaults.set(value, forKey: ThemeKeys.AutomaticBrightness.thresholdValue)
        brightnessChanged()
    }

    public func brightnessChanged() {
        if automaticBrightnessIsOn {
            updateThemeBasedOnBrightness()
        }
    }

    public func getNormalSavedTheme() -> ThemeType {
        if let savedThemeDescription = userDefaults.string(forKey: ThemeKeys.themeName),
           let savedTheme = ThemeType(rawValue: savedThemeDescription) {
            return savedTheme
        }

        return getSystemThemeType()
    }

    // MARK: - Private methods

    private func migrateSingleWindowPrivateDefaultsToMultiWindow(for window: UUID) {
        // Migrate old private setting to our window-based settings
        let oldPrivateSetting = userDefaults.bool(forKey: ThemeKeys.PrivateMode.legacy_isOn)
        let newSettings: KeyedPrivateModeFlags = [window.uuidString: NSNumber(value: oldPrivateSetting)]
        userDefaults.set(newSettings, forKey: ThemeKeys.PrivateMode.byWindowUUID)
    }

    private func updateSavedTheme(to newTheme: ThemeType) {
        // We never want to save the private theme because it's meant to override
        // whatever current theme is set. This means that we need to know the theme
        // before we went into private mode, in order to be able to return to it.
        guard newTheme != .privateMode else { return }
        userDefaults.set(newTheme.rawValue, forKey: ThemeKeys.themeName)
    }

    private func updateCurrentTheme(to newTheme: ThemeType, for window: UUID) {
        windowThemeState[window] = newThemeForType(newTheme)

        // Overwrite the user interface style on the window attached to our scene
        // once we have multiple scenes we need to update all of them

        let style = self.currentTheme(for: window).type.getInterfaceStyle()
        self.windows[window]?.overrideUserInterfaceStyle = style

        mainQueue.ensureMainThread { [weak self] in
            // Eventually WindowUUID and its extensions will be moved into BrowserKit. [FXIOS-9145]
            // Once that happens we should replace this string literal with `WindowUUID.userInfoKey`
            self?.notificationCenter.post(name: .ThemeDidChange, withUserInfo: ["windowUUID": window])
        }
    }

    private func fetchSavedThemeType(for window: UUID) -> ThemeType {
        if privateModeIsOn(for: window) { return .privateMode }
        if nightModeIsOn { return .dark }

        return getNormalSavedTheme()
    }

    private func getSystemThemeType() -> ThemeType {
        return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? ThemeType.dark : ThemeType.light
    }

    private func newThemeForType(_ type: ThemeType) -> Theme {
        switch type {
        case .light:
            return LightTheme()
        case .dark:
            return DarkTheme()
        case .privateMode:
            return PrivateModeTheme()
        }
    }

    private func updateThemeBasedOnBrightness() {
        allWindowUUIDs.forEach { uuid in
            let currentValue = Float(UIScreen.main.brightness)

            if currentValue < automaticBrightnessValue {
                changeCurrentTheme(.dark, for: uuid)
            } else {
                changeCurrentTheme(.light, for: uuid)
            }
        }
    }

    // MARK: - Notifiable

    public func handleNotifications(_ notification: Notification) {
        switch notification.name {
        case UIScreen.brightnessDidChangeNotification:
            brightnessChanged()
        case UIApplication.didBecomeActiveNotification:
            self.systemThemeChanged()
        default:
            return
        }
    }
}
