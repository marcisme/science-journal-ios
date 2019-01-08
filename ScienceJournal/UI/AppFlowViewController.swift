/*
 *  Copyright 2019 Google Inc. All Rights Reserved.
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

import UIKit

import third_party_objective_c_material_components_ios_components_Dialogs_Dialogs

/// The primary view controller for Science Journal which owns the navigation controller and manages
/// all other flows and view controllers.
class AppFlowViewController: UIViewController {

  /// The account user manager for the current account. Exposed for testing. If the current
  /// account's ID matches the existing accountUserManager account ID, this returns the existing
  /// manager. If not, a new manager is created for the current account and returned.
  var currentAccountUserManager: AccountUserManager? {
    guard let account = accountsManager.currentAccount else { return nil }

    if _currentAccountUserManager == nil || _currentAccountUserManager!.account.ID != account.ID {
      _currentAccountUserManager = AccountUserManager(account: account,
                                                      driveConstructor: driveConstructor,
                                                      networkAvailability: networkAvailability,
                                                      sensorController: sensorController)
    }
    return _currentAccountUserManager
  }

  private var _currentAccountUserManager: AccountUserManager?

  /// The device preference manager. Exposed for testing.
  let devicePreferenceManager = DevicePreferenceManager()

  /// The root user manager. Exposed for testing.
  let rootUserManager: RootUserManager

  /// The accounts manager. Exposed so the AppDelegate can ask for reauthentication and related
  /// tasks, as well as testing.
  let accountsManager: AccountsManager

  private let analyticsReporter: AnalyticsReporter
  private let commonUIComponents: CommonUIComponents
  private let drawerConfig: DrawerConfig
  private let driveConstructor: DriveConstructor
  private var existingDataMigrationManager: ExistingDataMigrationManager?
  private var existingDataOptionsVC: ExistingDataOptionsViewController?
  private let feedbackReporter: FeedbackReporter
  private let networkAvailability: NetworkAvailability
  #if FEATURE_FIREBASE_RC
  private let remoteConfigManager: RemoteConfigManager
  #endif
  private let queue = GSJOperationQueue()
  private let sensorController: SensorController
  private var shouldShowPreferenceMigrationMessage = false

  /// The current user flow view controller, if it exists.
  private weak var userFlowViewController: UserFlowViewController?

  #if FEATURE_FIREBASE_RC
  /// Designated initializer.
  ///
  /// - Parameters:
  ///   - accountsManager: The accounts manager.
  ///   - analyticsReporter: The analytics reporter.
  ///   - commonUIComponents: Common UI components.
  ///   - drawerConfig: The drawer config.
  ///   - driveConstructor: The drive constructor.
  ///   - feedbackReporter: The feedback reporter.
  ///   - networkAvailability: Network availability.
  ///   - remoteConfigManager: The remote config manager.
  ///   - sensorController: The sensor controller.
  init(accountsManager: AccountsManager,
       analyticsReporter: AnalyticsReporter,
       commonUIComponents: CommonUIComponents,
       drawerConfig: DrawerConfig,
       driveConstructor: DriveConstructor,
       feedbackReporter: FeedbackReporter,
       networkAvailability: NetworkAvailability,
       remoteConfigManager: RemoteConfigManager,
       sensorController: SensorController) {
    self.accountsManager = accountsManager
    self.analyticsReporter = analyticsReporter
    self.commonUIComponents = commonUIComponents
    self.drawerConfig = drawerConfig
    self.driveConstructor = driveConstructor
    self.feedbackReporter = feedbackReporter
    self.networkAvailability = networkAvailability
    self.remoteConfigManager = remoteConfigManager
    self.sensorController = sensorController
    rootUserManager = RootUserManager(sensorController: sensorController)
    super.init(nibName: nil, bundle: nil)

    // Register as the delegate for AccountsManager.
    self.accountsManager.delegate = self

    // If a user was denied permission to use Science Journal by their domain administrator, this
    // notification will be fired.
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(presentPermissionDenial),
                                           name: .userDeniedServerPermission,
                                           object: nil)
    // If a user should be forced to sign in from outside the sign in flow (e.g. their account was
    // invalid on foreground or they deleted an account), this notification will be fired.
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(forceSignInViaNotification),
                                           name: .userWillBeSignedOut,
                                           object: nil)
    #if SCIENCEJOURNAL_DEV_BUILD || SCIENCEJOURNAL_DOGFOOD_BUILD
    // If we should create root user data to test the claim flow, this notification will be fired.
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(debug_createRootUserData),
                                           name: .DEBUG_createRootUserData,
                                           object: nil)
    // If we should create root user data and force auth to test the migration flow, this
    // notification will be fired.
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(debug_forceAuth),
                                           name: .DEBUG_forceAuth,
                                           object: nil)
    #endif  // SCIENCEJOURNAL_DEV_BUILD || SCIENCEJOURNAL_DOGFOOD_BUILD
  }
  #else
  /// Designated initializer.
  ///
  /// - Parameters:
  ///   - accountsManager: The accounts manager.
  ///   - analyticsReporter: The analytics reporter.
  ///   - commonUIComponents: Common UI components.
  ///   - drawerConfig: The drawer config.
  ///   - driveConstructor: The drive constructor.
  ///   - feedbackReporter: The feedback reporter.
  ///   - networkAvailability: Network availability.
  ///   - sensorController: The sensor controller.
  init(accountsManager: AccountsManager,
       analyticsReporter: AnalyticsReporter,
       commonUIComponents: CommonUIComponents,
       drawerConfig: DrawerConfig,
       driveConstructor: DriveConstructor,
       feedbackReporter: FeedbackReporter,
       networkAvailability: NetworkAvailability,
       sensorController: SensorController) {
    self.accountsManager = accountsManager
    self.analyticsReporter = analyticsReporter
    self.commonUIComponents = commonUIComponents
    self.drawerConfig = drawerConfig
    self.driveConstructor = driveConstructor
    self.feedbackReporter = feedbackReporter
    self.networkAvailability = networkAvailability
    self.sensorController = sensorController
    rootUserManager = RootUserManager(sensorController: sensorController)
    super.init(nibName: nil, bundle: nil)

    // Register as the delegate for AccountsManager.
    self.accountsManager.delegate = self

    // If a user was denied permission to use Science Journal by their domain administrator, this
    // notification will be fired.
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(presentPermissionDenial),
                                           name: .userDeniedServerPermission,
                                           object: nil)
    // If a user should be forced to sign in from outside the sign in flow (e.g. their account was
    // invalid on foreground or they deleted an account), this notification will be fired.
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(forceSignInViaNotification),
                                           name: .userWillBeSignedOut,
                                           object: nil)
    #if SCIENCEJOURNAL_DEV_BUILD || SCIENCEJOURNAL_DOGFOOD_BUILD
    // If we should create root user data to test the claim flow, this notification will be fired.
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(debug_createRootUserData),
                                           name: .DEBUG_createRootUserData,
                                           object: nil)
    // If we should create root user data and force auth to test the migration flow, this
    // notification will be fired.
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(debug_forceAuth),
                                           name: .DEBUG_forceAuth,
                                           object: nil)
    #endif  // SCIENCEJOURNAL_DEV_BUILD || SCIENCEJOURNAL_DOGFOOD_BUILD
  }
  #endif

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    if accountsManager.supportsAccounts {
      accountsManager.signInAsCurrentAccount { (signInSuccess, forceSignIn) in
        self.showCurrentUserOrSignIn()
      }
    } else {
      showNonAccountUser(animated: false)
    }
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    return children.last?.preferredStatusBarStyle ?? .lightContent
  }

  private func showCurrentUserOrSignIn() {
    guard let accountUserManager = currentAccountUserManager else {
      print("[AppFlowViewController] No current account user manager, must sign in.")
      showSignIn()
      return
    }

    let existingDataMigrationManager =
        ExistingDataMigrationManager(accountUserManager: accountUserManager,
                                     rootUserManager: rootUserManager)
    let userAssetManager = UserAssetManager(driveSyncManager: accountUserManager.driveSyncManager,
                                            metadataManager: accountUserManager.metadataManager,
                                            sensorDataManager: accountUserManager.sensorDataManager)
    let accountUserFlow = UserFlowViewController(
        accountsManager: accountsManager,
        analyticsReporter: analyticsReporter,
        commonUIComponents: commonUIComponents,
        devicePreferenceManager: devicePreferenceManager,
        drawerConfig: drawerConfig,
        existingDataMigrationManager: existingDataMigrationManager,
        feedbackReporter: feedbackReporter,
        networkAvailability: networkAvailability,
        sensorController: sensorController,
        shouldShowPreferenceMigrationMessage: shouldShowPreferenceMigrationMessage,
        userAssetManager: userAssetManager,
        userManager: accountUserManager)
    accountUserFlow.delegate = self
    userFlowViewController = accountUserFlow
    transitionToViewController(accountUserFlow)

    // Set to false now so we don't accidently cache true and show it again when we don't want to.
    shouldShowPreferenceMigrationMessage = false
  }

  private func showNonAccountUser(animated: Bool) {
    let userAssetManager = UserAssetManager(driveSyncManager: rootUserManager.driveSyncManager,
                                            metadataManager: rootUserManager.metadataManager,
                                            sensorDataManager: rootUserManager.sensorDataManager)
    let userFlow = UserFlowViewController(accountsManager: accountsManager,
                                          analyticsReporter: analyticsReporter,
                                          commonUIComponents: commonUIComponents,
                                          devicePreferenceManager: devicePreferenceManager,
                                          drawerConfig: drawerConfig,
                                          existingDataMigrationManager: nil,
                                          feedbackReporter: feedbackReporter,
                                          networkAvailability: networkAvailability,
                                          sensorController: sensorController,
                                          shouldShowPreferenceMigrationMessage: false,
                                          userAssetManager: userAssetManager,
                                          userManager: rootUserManager)
    userFlow.delegate = self
    userFlowViewController = userFlow
    transitionToViewController(userFlow, animated: animated)
  }

  // Transitions to the sign in flow with an optional completion block to fire when the flow
  // has been shown.
  private func showSignIn(completion: (() -> Void)? = nil) {
    let signInFlow = SignInFlowViewController(accountsManager: accountsManager,
                                              analyticsReporter: analyticsReporter,
                                              rootUserManager: rootUserManager,
                                              sensorController: sensorController)
    signInFlow.delegate = self
    transitionToViewController(signInFlow, completion: completion)
  }

  /// Handles a file import URL if possible.
  ///
  /// - Parameter url: A file URL.
  /// - Returns: True if the URL can be handled, otherwise false.
  func handleImportURL(_ url: URL) -> Bool {
    guard let userFlowViewController = userFlowViewController else {
      showSnackbar(withMessage: String.importSignInError)
      return false
    }
    return userFlowViewController.handleImportURL(url)
  }

  // MARK: - Private

  // Wrapper method for use with notifications, where notifications would attempt to push their
  // notification object into the completion argument of `forceUserSignIn` incorrectly.
  @objc func forceSignInViaNotification() {
    forceUserSignIn()
  }

  // Forces a user to sign in if they're not already in the sign in flow, with an optional block
  // to run once the sign in flow is presented.
  @objc private func forceUserSignIn(completion: (() -> Void)? = nil) {
    guard !(children.last is SignInFlowViewController) else { return }
    showSignIn(completion: completion)
  }

  @objc private func presentPermissionDenial() {
    // Convenience method for removing the current account and forcing a user to sign in, which
    // is a possibility in two cases here.
    func removeAccountAndForceSignIn(_ showAccountPickerImmediately: Bool = false) {
      accountsManager.signOutCurrentAccount()
      forceUserSignIn {
        if showAccountPickerImmediately {
          self.presentAccountSelector()
        }
      }
    }

    // If we can't grab the top view controller, just force sign in since that's the result we're
    // looking for anyway.
    guard let topVC = children.last else {
      removeAccountAndForceSignIn()
      return
    }

    // Alert the user and give them the option to directly switch accounts or cancel out to the
    // welcome screen.
    let alertController = MDCAlertController(title: String.serverPermissionDeniedTitle,
                                             message: String.serverPermissionDeniedMessage)
    alertController.addAction(MDCAlertAction(title: String.serverSwitchAccountsTitle,
                                             handler: { (_) in removeAccountAndForceSignIn(true) }))
    alertController.addAction(MDCAlertAction(title: String.actionCancel,
                                             handler: { (_) in removeAccountAndForceSignIn() }))
    alertController.accessibilityViewIsModal = true

    // Remove ability to dismiss the dialog by tapping in the background.
    alertController.mdc_dialogPresentationController?.dismissOnBackgroundTap = false

    topVC.present(alertController, animated: true)
  }

  /// Migrates preferences and removes bluetooth devices if this account is signing in for the first
  /// time.
  ///
  /// - Parameter accountID: The account ID.
  /// - Returns: Whether the user should be messaged saying that preferences were migrated.
  private func migratePreferencesAndRemoveBluetoothDevicesIfNeeded(forAccountID accountID: String)
      -> Bool {
    // If an account does not yet have a directory, this is its first time signing in. Each new
    // account should have preferences migrated from the root user.
    let shouldMigratePrefs = !AccountUserManager.hasRootDirectoryForAccount(withID: accountID)
    if shouldMigratePrefs, let accountUserManager = currentAccountUserManager {
      let existingDataMigrationManager =
          ExistingDataMigrationManager(accountUserManager: accountUserManager,
                                       rootUserManager: rootUserManager)
      existingDataMigrationManager.migratePreferences()
      existingDataMigrationManager.removeAllBluetoothDevices()
    }

    let wasAppUsedByRootUser = rootUserManager.hasDirectory
    return wasAppUsedByRootUser && shouldMigratePrefs
  }

  private func performMigrationIfNeededAndContinueSignIn() {
    guard let accountID = accountsManager.currentAccount?.ID else {
      sjlog_error("Accounts manager does not have a current account after sign in flow completion.",
                  category: .general)
      // This method should never be called if the current user doesn't exist but in case of error,
      // show sign in again.
      showSignIn()
      return
    }

    // Unwrapping `currentAccountUserManager` would initialize a new instance of the account manager
    // if a current account exists. This creates the account's directory. However, the migration
    // method checks to see if this directory exists or not, so we must not call it until after
    // migration.
    shouldShowPreferenceMigrationMessage =
        migratePreferencesAndRemoveBluetoothDevicesIfNeeded(forAccountID: accountID)

    // Show the migration options if a choice has never been selected.
    guard !devicePreferenceManager.hasAUserChosenAnExistingDataMigrationOption else {
      showCurrentUserOrSignIn()
      return
    }

    guard let accountUserManager = currentAccountUserManager else {
      // This delegate method should never be called if the current user doesn't exist but in case
      // of error, show sign in again.
      showSignIn()
      return
    }

    let existingDataMigrationManager =
        ExistingDataMigrationManager(accountUserManager: accountUserManager,
                                     rootUserManager: rootUserManager)
    if existingDataMigrationManager.hasExistingExperiments {
      self.existingDataMigrationManager = existingDataMigrationManager
      let existingDataOptionsVC = ExistingDataOptionsViewController(
          analyticsReporter: analyticsReporter,
          numberOfExistingExperiments: existingDataMigrationManager.numberOfExistingExperiments)
      self.existingDataOptionsVC = existingDataOptionsVC
      existingDataOptionsVC.delegate = self
      transitionToViewController(existingDataOptionsVC)
    } else {
      showCurrentUserOrSignIn()
    }
  }

}

// MARK: - AccountsManagerDelegate

extension AppFlowViewController: AccountsManagerDelegate {

  func deleteAllUserDataForIdentity(withID identityID: String) {
    // Remove the persistent store before deleting the DB files to avoid a log error. Use
    // `_currentAccountUserManager`, because `currentAccountUserManager` will return nil because
    // `accountsManager.currentAccount` is now nil. Also, remove the current account user manager so
    // the sensor data manager is recreated if this same user logs back in immediately.
    _currentAccountUserManager?.sensorDataManager.removeStore()
    _currentAccountUserManager = nil
    do {
      try AccountDeleter(accountID: identityID).deleteData()
    } catch {
      print("Failed to delete user data: \(error.localizedDescription)")
    }
  }

}

// MARK: - ExistingDataOptionsDelegate

extension AppFlowViewController: ExistingDataOptionsDelegate {

  func existingDataOptionsViewControllerDidSelectSaveAllExperiments() {
    guard let existingDataOptionsVC = existingDataOptionsVC else { return }
    devicePreferenceManager.hasAUserChosenAnExistingDataMigrationOption = true
    let spinnerViewController = SpinnerViewController()
    spinnerViewController.present(fromViewController: existingDataOptionsVC) {
      self.existingDataMigrationManager?.migrateAllExperiments(completion: { (errors) in
        spinnerViewController.dismissSpinner() {
          self.showCurrentUserOrSignIn()
          if !errors.isEmpty {
            showSnackbar(withMessage: String.claimExperimentsErrorMessage)
          }
        }
      })
    }
  }

  func existingDataOptionsViewControllerDidSelectDeleteAllExperiments() {
    devicePreferenceManager.hasAUserChosenAnExistingDataMigrationOption = true
    existingDataMigrationManager?.removeAllExperimentsFromRootUser()
    showCurrentUserOrSignIn()
  }

  func existingDataOptionsViewControllerDidSelectSelectExperimentsToSave() {
    devicePreferenceManager.hasAUserChosenAnExistingDataMigrationOption = true
    // If the user wants to manually select experiments to claim, nothing needs to be done now. They
    // will see the option to claim experiments in the experiments list.
    showCurrentUserOrSignIn()
  }

}

// MARK: - SignInFlowViewControllerDelegate

extension AppFlowViewController: SignInFlowViewControllerDelegate {

  func signInFlowDidCompleteWithAccount() {
    performMigrationIfNeededAndContinueSignIn()
  }

  func signInFlowDidCompleteWithoutAccount() {
    showNonAccountUser(animated: true)
  }

}

// MARK: - UserFlowViewControllerDelegate

extension AppFlowViewController: UserFlowViewControllerDelegate {

  func presentAccountSelector() {
    accountsManager.presentSignIn(fromViewController: self) { (signInSuccess, shouldForceSignIn) in
      if signInSuccess == false && shouldForceSignIn == false {
        // User changed nothing.
        return
      } else if shouldForceSignIn {
        // We should force the user to sign in now.
        self.showCurrentUserOrSignIn()
      } else if signInSuccess {
        // If signInSuccess is true, we need to handle the change of account.
        self.performMigrationIfNeededAndContinueSignIn()
      }
    }
  }

}

#if SCIENCEJOURNAL_DEV_BUILD || SCIENCEJOURNAL_DOGFOOD_BUILD
// MARK: - Debug additions for creating data and testing claim and migration flows in-app.

extension AppFlowViewController {

  @objc private func debug_createRootUserData() {
    guard let settingsVC = userFlowViewController?.settingsVC else { return }
    let spinnerVC = SpinnerViewController()
    spinnerVC.present(fromViewController: settingsVC) {
      self.rootUserManager.metadataManager.debug_createRootUserData() {
        DispatchQueue.main.async {
          self.userFlowViewController?.experimentsListVC?.refreshUnclaimedExperiments()
          spinnerVC.dismissSpinner()
        }
      }
    }
  }

  @objc private func debug_forceAuth() {
    devicePreferenceManager.hasAUserChosenAnExistingDataMigrationOption = false
    devicePreferenceManager.hasAUserCompletedPermissionsGuide = false
    NotificationCenter.default.post(name: .DEBUG_destroyCurrentUser, object: nil, userInfo: nil)
    forceUserSignIn()
  }

}
#endif  // SCIENCEJOURNAL_DEV_BUILD || SCIENCEJOURNAL_DOGFOOD_BUILD