#!/usr/bin/env ruby
# frozen_string_literal: true

# Configure Xcode project for Rust static library integration.
# Usage: ruby scripts/setup-xcode.rb

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../gahpc.xcodeproj', __dir__)
RUST_LIB_DIR = File.expand_path('../ahpc-rs/target/release', __dir__)
BRIDGING_HEADER = 'gahpc/gahpc-Bridging-Header.h'

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
raise 'No target found' unless target

puts "📦 Project: #{project.path.basename}"
puts "🎯 Target:  #{target.name}"

# ── 1. Add source files to the group ──

group = project.main_group['gahpc'] || project.main_group.new_group('gahpc')

new_files = %w[
  ConfigModel.swift
  RustBridge.swift
  gahpc-Bridging-Header.h
]

new_files.each do |filename|
  path = File.join(File.dirname(PROJECT_PATH), 'gahpc', filename)
  next unless File.exist?(path)

  # Check if already added
  existing = group.files.find { |f| f.display_name == filename }
  if existing
    puts "   ⏭  #{filename} already in project"
    next
  end

  file_ref = group.new_reference(path)
  puts "   ➕ #{filename} → group"

  # Add .swift files to Sources build phase
  if filename.end_with?('.swift')
    target.source_build_phase.add_file_reference(file_ref)
    puts "      └─ added to Sources phase"
  end

  # Mark bridging header as such
  if filename.end_with?('-Bridging-Header.h')
    # Don't add headers to compile sources
    puts "      └─ bridging header"
  end
end

# ── 2. Add Shell Script build phase for Rust ──

script_phase_name = 'Build Rust Static Library'
existing_phase = target.shell_script_build_phases.find { |p| p.name == script_phase_name }

unless existing_phase
  phase = target.new_shell_script_build_phase(script_phase_name)
  phase.shell_script = <<~BASH
    # Build Rust static library (x86_64 only)
    set -euo pipefail
    export PATH="$HOME/.cargo/bin:$PATH"
    cd "$SRCROOT"/ahpc-rs
    echo "🔨 Building Rust static library (x86_64)..."
    cargo build --release --target x86_64-apple-darwin 2>&1 | sed 's/^/   [x86_64] /'
    cp target/x86_64-apple-darwin/release/libahpc.a target/release/libahpc.a
    echo "✅ Rust x86_64 build complete"
  BASH

  # Declare output so Xcode knows when to re-run
  phase.output_paths = ['$(PROJECT_DIR)/ahpc-rs/target/release/libahpc.a']
  phase.input_paths = [
    '$(PROJECT_DIR)/ahpc-rs/Cargo.toml',
    '$(PROJECT_DIR)/ahpc-rs/Cargo.lock',
    '$(PROJECT_DIR)/ahpc-rs/src/lib.rs',
    '$(PROJECT_DIR)/ahpc-rs/src/main.rs',
    '$(PROJECT_DIR)/ahpc-rs/src/config.rs',
    '$(PROJECT_DIR)/ahpc-rs/src/connection.rs',
    '$(PROJECT_DIR)/ahpc-rs/src/crypto.rs',
  ]

  # Move to before Sources phase
  phase_index = target.build_phases.index(phase)
  sources_index = target.build_phases.index(target.source_build_phase)
  if phase_index && sources_index && phase_index > sources_index
    target.build_phases.move_from(phase_index, sources_index)
  end
  puts "   ➕ Shell Script phase: #{script_phase_name}"
else
  puts "   ⏭  Shell Script phase already exists"
end

# ── 3. Update build settings ──

configs = target.build_configurations
configs.each do |config|
  # Library search paths
  lib_paths = config.build_settings['LIBRARY_SEARCH_PATHS'] || ['$(inherited)']
  lib_paths = [lib_paths] unless lib_paths.is_a?(Array)
  rust_lib_rel = '$(PROJECT_DIR)/ahpc-rs/target/release'
  unless lib_paths.include?(rust_lib_rel)
    lib_paths << rust_lib_rel
    config.build_settings['LIBRARY_SEARCH_PATHS'] = lib_paths
    puts "   📐 #{config.name}: LIBRARY_SEARCH_PATHS += #{rust_lib_rel}"
  end

  # Linker flags
  ld_flags = config.build_settings['OTHER_LDFLAGS'] || ['$(inherited)']
  ld_flags = [ld_flags] unless ld_flags.is_a?(Array)
  unless ld_flags.include?('-lahpc')
    ld_flags << '-lahpc'
    config.build_settings['OTHER_LDFLAGS'] = ld_flags
    puts "   📐 #{config.name}: OTHER_LDFLAGS += -lahpc"
  end

  # Bridging header
  unless config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] == BRIDGING_HEADER
    config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = BRIDGING_HEADER
    puts "   📐 #{config.name}: SWIFT_OBJC_BRIDGING_HEADER = #{BRIDGING_HEADER}"
  end
end

# ── 4. Save ──

project.save
puts "\n✅ Xcode project updated successfully!"
