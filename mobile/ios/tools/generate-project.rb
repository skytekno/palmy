# Run with GEM_HOME=../.tools/gems ruby tools/generate-project.rb from mobile/ios.
require 'xcodeproj'
require 'fileutils'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(root, 'Palmy.xcodeproj'))
app = project.new_target(:application, 'Palmy', :ios, '17.0')
sources = project.main_group.new_group('Palmy', 'Palmy')
sources.new_file('PalmyApp.swift').tap { |f| app.source_build_phase.add_file_reference(f) }
# Compile core sources directly into the app; Swift package remains independently testable.
core = project.new_target(:framework, 'PalmyCore', :ios, '17.0')
core_group = project.main_group.new_group('Core', 'Sources/PalmyCore')
Dir.glob(File.join(root, 'Sources/PalmyCore/*.swift')).sort.each { |file| core.source_build_phase.add_file_reference(core_group.new_file(File.basename(file))) }
app.add_dependency(core)
app.frameworks_build_phase.add_file_reference(core.product_reference)
embed = app.new_copy_files_build_phase('Embed Frameworks'); embed.dst_subfolder_spec = '10'
embedded = embed.add_file_reference(core.product_reference); embedded.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
ui_tests = project.new_target(:ui_test_bundle, 'PalmyUITests', :ios, '17.0')
ui_group = project.main_group.new_group('UITests', 'UITests')
Dir.glob(File.join(root, 'UITests/*.swift')).sort.each { |file| ui_tests.source_build_phase.add_file_reference(ui_group.new_file(File.basename(file))) }
ui_tests.add_dependency(app)
[app, core, ui_tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '6.0'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = { app => 'com.palmy.app', core => 'com.palmy.core', ui_tests => 'com.palmy.uitests' }.fetch(target)
    config.build_settings['MARKETING_VERSION'] = '0.1.0'
    config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = config.name == 'Debug' ? 'DEBUG' : ''
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    config.build_settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
    config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'YES'
    config.build_settings['INFOPLIST_KEY_ITSAppUsesNonExemptEncryption'] = 'NO'
    if target == app
      config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
      config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
      config.build_settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Palmy'
      config.build_settings['INFOPLIST_FILE'] = config.name == 'Debug' ? 'Palmy/Info-Debug.plist' : 'Palmy/Info-Release.plist'
    elsif target == core
      config.build_settings['DEFINES_MODULE'] = 'YES'
      config.build_settings['SKIP_INSTALL'] = 'YES'
    else
      config.build_settings['TEST_TARGET_NAME'] = 'Palmy'
      config.build_settings['SKIP_INSTALL'] = 'YES'
    end
  end
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(ui_tests)
scheme.test_action.should_use_launch_scheme_args_env = false
scheme.test_action.environment_variables = Xcodeproj::XCScheme::EnvironmentVariables.new([
  { :key => 'PALMY_UI_LIVE_API', :value => '$(PALMY_UI_LIVE_API)', :enabled => true }
])
scheme.save_as(File.join(root, 'Palmy.xcodeproj'), 'Palmy', true)
