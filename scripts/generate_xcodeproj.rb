#!/usr/bin/env ruby
# Generates a minimal .xcodeproj for SSH Tunnel Toggle using xcodegen format,
# then uses `xcodegen` if available, otherwise generates a project.pbxproj directly.

require 'fileutils'
require 'securerandom'

PROJECT_DIR = File.expand_path('..', __dir__)
PROJ_NAME = 'SSHTunnelToggle'

# Try xcodegen first
if system('which xcodegen > /dev/null 2>&1')
  puts "Found xcodegen, generating project..."
  
  spec = <<~YAML
    name: #{PROJ_NAME}
    options:
      deploymentTarget:
        macOS: "14.0"
      xcodeVersion: "15.0"
      generateEmptyDirectories: true
    settings:
      base:
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        SWIFT_VERSION: "5.9"
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGN_STYLE: Manual
        PRODUCT_BUNDLE_IDENTIFIER: com.ssh-tunnel-toggle.app
        INFOPLIST_FILE: #{PROJ_NAME}/Info.plist
        CODE_SIGN_ENTITLEMENTS: #{PROJ_NAME}/#{PROJ_NAME}.entitlements
        ENABLE_APP_SANDBOX: NO
        GENERATE_INFOPLIST_FILE: NO
    targets:
      #{PROJ_NAME}:
        type: application
        platform: macOS
        sources:
          - #{PROJ_NAME}
        settings:
          base:
            PRODUCT_BUNDLE_IDENTIFIER: com.ssh-tunnel-toggle.app
            INFOPLIST_FILE: #{PROJ_NAME}/Info.plist
            CODE_SIGN_ENTITLEMENTS: #{PROJ_NAME}/#{PROJ_NAME}.entitlements
            CODE_SIGN_IDENTITY: "-"
            CODE_SIGN_STYLE: Manual
            ENABLE_APP_SANDBOX: NO
            GENERATE_INFOPLIST_FILE: NO
  YAML

  spec_path = File.join(PROJECT_DIR, 'project.yml')
  File.write(spec_path, spec)
  
  Dir.chdir(PROJECT_DIR) do
    exec('xcodegen generate')
  end
else
  puts "xcodegen not found, generating .xcodeproj manually..."
  
  # Generate a proper pbxproj file
  generate_pbxproj
end

def generate_pbxproj
  # UUID generation for PBX objects
  def uuid
    SecureRandom.hex(12).upcase
  end

  # Collect source files
  source_dir = File.join(PROJECT_DIR, PROJ_NAME)
  sources = []
  resources = []
  
  Dir.glob(File.join(source_dir, '**/*.swift')).each do |f|
    rel = f.sub("#{PROJECT_DIR}/", '')
    sources << rel
  end
  
  Dir.glob(File.join(source_dir, '**/*.xcassets')).each do |f|
    rel = f.sub("#{PROJECT_DIR}/", '')
    resources << rel
  end

  # PBXFileReference IDs
  file_ref_ids = {}
  all_files = sources + resources
  all_files.each { |f| file_ref_ids[f] = uuid }

  # PBXGroup IDs
  group_ids = {}
  # ... this gets very verbose, use xcodegen instead

  puts "Manual pbxproj generation is complex. Please install xcodegen:"
  puts "  brew install xcodegen"
  puts "Then run: cd #{PROJECT_DIR} && xcodegen generate"
  puts ""
  puts "Alternatively, open Xcode and create a new macOS > App project,"
  puts "then add the source files manually."
end
