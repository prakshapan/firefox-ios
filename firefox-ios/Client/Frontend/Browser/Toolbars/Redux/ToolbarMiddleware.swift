// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import ToolbarKit

class ToolbarMiddleware: FeatureFlaggable {
    private let profile: Profile
    private let manager: ToolbarManager
    private let logger: Logger

    init(profile: Profile = AppContainer.shared.resolve(),
         manager: ToolbarManager = DefaultToolbarManager(),
         logger: Logger = DefaultLogger.shared) {
        self.profile = profile
        self.manager = manager
        self.logger = logger
    }

    lazy var toolbarProvider: Middleware<AppState> = { state, action in
        if let action = action as? GeneralBrowserMiddlewareAction {
            self.resolveGeneralBrowserMiddlewareActions(action: action, state: state)
        } else if let action = action as? ToolbarMiddlewareAction {
            self.resolveToolbarMiddlewareActions(action: action, state: state)
        }
    }

    private func resolveGeneralBrowserMiddlewareActions(action: GeneralBrowserMiddlewareAction, state: AppState) {
        let uuid = action.windowUUID

        switch action.actionType {
        case GeneralBrowserMiddlewareActionType.browserDidLoad:
            let actions = self.loadNavigationToolbarElements()
            let displayBorder = self.shouldDisplayNavigationToolbarBorder(state: state, windowUUID: action.windowUUID)

            let action = ToolbarAction(actions: actions,
                                       displayBorder: displayBorder,
                                       windowUUID: uuid,
                                       actionType: ToolbarActionType.didLoadToolbars)
            store.dispatch(action)

        default:
            break
        }
    }

    private func resolveToolbarMiddlewareActions(action: ToolbarMiddlewareAction, state: AppState) {
        switch action.actionType {
        case ToolbarMiddlewareActionType.didTapButton:
            resolveToolbarMiddlewareButtonTapActions(action: action, state: state)

        default:
            break
        }
    }

    private func resolveToolbarMiddlewareButtonTapActions(action: ToolbarMiddlewareAction, state: AppState) {
        guard let buttonType = action.buttonType, let gestureType = action.gestureType else { return }

        let uuid = action.windowUUID
        switch gestureType {
        case .tap: handleToolbarButtonTapActions(actionType: buttonType, windowUUID: uuid)
        case .longPress: handleToolbarButtonLongPressActions(actionType: buttonType, windowUUID: uuid)
        }
    }

    private func loadNavigationToolbarElements() -> [ToolbarState.ActionState] {
        var elements = [ToolbarState.ActionState]()
        elements.append(ToolbarState.ActionState(actionType: .back,
                                                 iconName: StandardImageIdentifiers.Large.back,
                                                 isEnabled: false,
                                                 a11yLabel: .TabToolbarBackAccessibilityLabel,
                                                 a11yId: AccessibilityIdentifiers.Toolbar.backButton))
        elements.append(ToolbarState.ActionState(actionType: .forward,
                                                 iconName: StandardImageIdentifiers.Large.forward,
                                                 isEnabled: false,
                                                 a11yLabel: .TabToolbarForwardAccessibilityLabel,
                                                 a11yId: AccessibilityIdentifiers.Toolbar.forwardButton))
        elements.append(ToolbarState.ActionState(actionType: .home,
                                                 iconName: StandardImageIdentifiers.Large.home,
                                                 isEnabled: true,
                                                 a11yLabel: .TabToolbarHomeAccessibilityLabel,
                                                 a11yId: AccessibilityIdentifiers.Toolbar.homeButton))
        elements.append(ToolbarState.ActionState(actionType: .tabs,
                                                 iconName: StandardImageIdentifiers.Large.tabTray, // correct image
                                                 isEnabled: true,
                                                 a11yLabel: .TabsButtonShowTabsAccessibilityLabel,
                                                 a11yId: AccessibilityIdentifiers.Toolbar.tabsButton))
        elements.append(ToolbarState.ActionState(actionType: .menu,
                                                 iconName: StandardImageIdentifiers.Large.appMenu,
                                                 isEnabled: true,
                                                 a11yLabel: .AppMenu.Toolbar.MenuButtonAccessibilityLabel,
                                                 a11yId: AccessibilityIdentifiers.Toolbar.settingsMenuButton))
        return elements
    }

    private func shouldDisplayNavigationToolbarBorder(state: AppState, windowUUID: UUID) -> Bool {
        guard let browserState = state.screenState(BrowserViewControllerState.self,
                                                   for: .browserViewController,
                                                   window: windowUUID) else { return false }
        let toolbarState = browserState.toolbarState
        return manager.shouldDisplayNavigationBorder(toolbarPosition: toolbarState.toolbarPosition)
    }

    private func handleToolbarButtonTapActions(actionType: ToolbarState.ActionState.ActionType, windowUUID: UUID) {
        switch actionType {
        case .home:
            let action = GeneralBrowserAction(navigateToHome: true,
                                              windowUUID: windowUUID,
                                              actionType: GeneralBrowserActionType.goToHomepage)
            store.dispatch(action)

        default:
            break
        }
    }

    private func handleToolbarButtonLongPressActions(actionType: ToolbarState.ActionState.ActionType,
                                                     windowUUID: UUID) {
        switch actionType {
        default:
            break
        }
    }
}
