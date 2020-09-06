//
//  AppDelegate.swift
//  Pock
//
//  Created by Pierluigi Galdi on 08/09/17.
//  Copyright © 2017 Pierluigi Galdi. All rights reserved.
//

import Cocoa
import Defaults
import Preferences
import AppCenter
import AppCenterAnalytics
import AppCenterCrashes
import Magnet
@_exported import PockKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    static var `default`: AppDelegate {
        return NSApp.delegate as! AppDelegate
    }
    
    /// Core
    public private(set) var alertWindowController: AlertWindowController?
    public private(set) var navController:         PKTouchBarNavigationController?
    
    /// Timer
    fileprivate var automaticUpdatesTimer: Timer?
    
    /// Status bar Pock icon
    fileprivate let pockStatusbarIcon = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    
    /// Main Pock menu
    private lazy var mainPockMenu: NSMenu = {
        let menu = NSMenu(title: "Pock Options")
        menu.addItem(withTitle: "Preferences…".localized, action: #selector(openPreferences), keyEquivalent: ",")
        menu.addItem(withTitle: "Customize…".localized, action: #selector(openCustomization), keyEquivalent: "c")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Widgets Manager".localized, action: #selector(openWidgetsManager), keyEquivalent: "w")
        let advancedMenuItem = NSMenuItem(title: "Advanced".localized, action: nil, keyEquivalent: "")
        advancedMenuItem.submenu = advancedPockMenu
        menu.addItem(advancedMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Support this project".localized, action: #selector(openDonateURL),  keyEquivalent: "s")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Pock".localized, action: #selector(NSApp.terminate), keyEquivalent: "q")
        return menu
    }()
    
    private lazy var advancedPockMenu: NSMenu = {
        let menu = NSMenu(title: "Advanced".localized)
        let reloadItem = NSMenuItem(title: "Reload Pock".localized, action: #selector(reloadPock), keyEquivalent: "r")
        let relaunchItem = NSMenuItem(title: "Relaunch Pock".localized, action: #selector(relaunchPock), keyEquivalent: "R")
        relaunchItem.isAlternate = true
        menu.addItem(withTitle: "Re-Install default widgets".localized, action: #selector(installDefaultWidgets), keyEquivalent: "d")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(reloadItem)
        menu.addItem(relaunchItem)
        menu.addItem(withTitle: "Reload System Touch Bar".localized, action: #selector(reloadTouchBarServer), keyEquivalent: "a")
        return menu
    }()
    
    /// Preferences
    private let generalPreferencePane: GeneralPreferencePane = GeneralPreferencePane()
    private lazy var preferencesWindowController: PreferencesWindowController = {
        return PreferencesWindowController(preferencePanes: [generalPreferencePane])
    }()
    
    /// Widgets Manager
    private lazy var widgetsManagerWindowController: PreferencesWindowController = {
        return PreferencesWindowController(
            preferencePanes: [
                WidgetsManagerListPane(),
                WidgetsManagerInstallPane()
            ],
            hidesToolbarForSingleItem: false
        )
    }()
    
    /// Finish launching
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        /// Initialize Crashlytics
        #if !DEBUG
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist") {
            if let secrets = NSDictionary(contentsOfFile: path) as? [String: String], let secret = secrets["AppCenter"] {
                UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
                MSAppCenter.start(secret, withServices: [
                    MSAnalytics.self,
                    MSCrashes.self
                ])
            }
        }
        #endif
        
        /// Check for legacy hideControlStrip option
        if Defaults[.hideSystemControlStrip] == nil, let shouldHideControlStrip = Defaults[.hideControlStrip] {
            Defaults[.hideSystemControlStrip] = shouldHideControlStrip
            if shouldHideControlStrip && TouchBarHelper.isSystemControlStripVisible {
                alertWindowController = AlertWindowController(
                    title:   "Hide Control Strip".localized,
                    message: "Hide_Control_Strip_Message".localized,
                    action: AlertAction(
                        title: "Continue".localized,
                        action: {
                            TouchBarHelper.hideSystemControlStrip({ [weak self] success in
                                if success {
                                    Defaults[.hideControlStrip] = nil
                                }
                                self?.initialize()
                                self?.alertWindowController = nil
                            })
                        }
                    )
                )
                alertWindowController?.showWindow(nil)
            }else {
                self.initialize()
            }
        }else {
            self.initialize()
        }
        
        /// Set Pock inactive
        NSApp.deactivate()

    }
    
    private func initialize() {
        /// Check for accessibility (needed for badges to work)
        self.checkAccessibility()
        
        /// Check for status bar icon
        if let button = pockStatusbarIcon.button {
            button.image = NSImage(named: "pock-inner-icon")
            button.image?.isTemplate = true
            /// Create menu
            pockStatusbarIcon.menu = mainPockMenu
        }
        
        /// Check for updates
        async(after: 1) { [weak self] in
            self?.checkForUpdates()
        }
        
        /// Register for notification
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(toggleAutomaticUpdatesTimer),
                                                          name: .shouldEnableAutomaticUpdates,
                                                          object: nil)
        
        NSWorkspace.shared.notificationCenter.addObserver(self,
                                                          selector: #selector(reloadPock),
                                                          name: .shouldReloadPock,
                                                          object: nil)
        toggleAutomaticUpdatesTimer()
        registerGlobalHotKey()
        
        /// Present Pock
        reloadPock()
    }
    
    @objc func reloadPock() {
        navController?.dismiss()
        navController = nil
        let mainController: PockMainController = PockMainController.load()
        navController = PKTouchBarNavigationController(rootController: mainController)
    }
    
    @objc func relaunchPock() {
        PockHelper.default.relaunchPock()
    }
    
    @objc func reloadTouchBarServer() {
        PockHelper.default.reloadTouchBarServer() { [weak self] success in
            if success {
                self?.reloadPock()
            }
        }
    }
    
    @objc func installDefaultWidgets() {
        PockHelper.default.installDefaultWidgets()
    }
    
    private func registerGlobalHotKey() {
        if let keyCombo = KeyCombo(doubledCocoaModifiers: .control) {
            let hotKey = HotKey(identifier: "TogglePock", keyCombo: keyCombo, target: self, action: #selector(togglePock))
            hotKey.register()
        }
    }
    
    @objc private func togglePock() {
        if navController == nil {
            reloadPock()
        }else {
            navController?.dismiss()
            navController = nil
        }
    }
    
    @objc private func toggleAutomaticUpdatesTimer() {
        if Defaults[.enableAutomaticUpdates] {
            automaticUpdatesTimer = Timer.scheduledTimer(timeInterval: 86400 /*24h*/, target: self, selector: #selector(checkForUpdates), userInfo: nil, repeats: true)
        }else {
            automaticUpdatesTimer?.invalidate()
            automaticUpdatesTimer = nil
        }
    }
    
    /// Will terminate
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        NotificationCenter.default.removeObserver(self)
        navController?.dismiss()
        navController = nil
    }
    
    /// Check for updates
    @objc private func checkForUpdates() {
        generalPreferencePane.hasLatestVersion(completion: { [weak self] versionNumber, downloadURL in
            guard let versionNumber = versionNumber, let downloadURL = downloadURL else { return }
            self?.generalPreferencePane.newVersionAvailable = (versionNumber, downloadURL)
            async { [weak self] in
                self?.openPreferences()
            }
        })
    }
    
    /// Check for accessibility
    @discardableResult
    private func checkAccessibility() -> Bool {
        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options = [checkOptPrompt: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary?)
        return accessEnabled
    }
    
    /// Open preferences
    @objc private func openPreferences() {
        preferencesWindowController.show()
    }
    
    /// Open customization
    @objc private func openCustomization() {
        (navController?.rootController as? PockMainController)?.openCustomization()
    }
    
    /// Open widgets manager
    @objc internal func openWidgetsManager() {
        widgetsManagerWindowController.show()
    }
    
    /// Open donate url
    @objc private func openDonateURL() {
        guard let url = URL(string: "https://paypal.me/pigigaldi") else { return }
        NSWorkspace.shared.open(url)
    }
    
}
