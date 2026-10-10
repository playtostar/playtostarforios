#!/usr/bin/env ruby
# ============================================================
# 微信 OpenSDK (XCFramework) 一键集成到 Capacitor iOS 工程
# 幂等：重复运行不会重复添加同一引用 / 链接 / 标记。
# 运行目录：ios/App （本文件所在目录）
# ============================================================
require 'xcodeproj'

PROJ     = 'App.xcodeproj'
FW_NAME  = 'WechatOpenSDK-NoPay.xcframework'
SYS_FW   = %w[Security WebKit CoreGraphics].freeze
LD_FLAGS = %w[-ObjC].freeze

project = Xcodeproj::Project.open(PROJ)
target  = project.targets.find { |t| t.name == 'App' }
abort('未找到 target「App」，请确认在 ios/App 目录运行') unless target

# ---------- 1) xcframework 文件引用（App/Frameworks 组）----------
app_group = project.main_group.groups.find { |g| g.display_name == 'App' } ||
            project.main_group.find_subpath('App', true)
fw_group  = app_group.groups.find { |g| g.display_name == 'Frameworks' } ||
            app_group.new_group('Frameworks', 'Frameworks')

fw_ref = project.files.find { |f| f.path.to_s.end_with?(FW_NAME) } ||
         fw_group.new_file(FW_NAME)
fw_ref.explicit_file_type = 'wrapper.xcframework'

# ---------- 2) 链接到 Frameworks 构建阶段 ----------
unless target.frameworks_build_phase.files_references.include?(fw_ref)
  target.frameworks_build_phase.add_file_reference(fw_ref, true)
end

# ---------- 3) Embed & Sign（Copy Files → Frameworks，spec=10）----------
embed = target.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :frameworks } ||
        target.new_copy_files_build_phase('Embed Frameworks')
embed.symbol_dst_subfolder_spec = :frameworks
unless embed.files_references.include?(fw_ref)
  bf = embed.add_file_reference(fw_ref, true)
  bf.settings = { 'ATTRIBUTES' => ['Code Sign On Copy'] }
end

# ---------- 4) 系统框架（随当前 SDK 解析，sourceTree=SDKROOT）----------
SYS_FW.each do |name|
  file = "#{name}.framework"
  ref = project.files.find { |f| f.path == file && f.source_tree == 'SDKROOT' }
  unless ref
    ref = project.main_group.new_file(file)
    ref.source_tree = 'SDKROOT'
  end
  unless target.frameworks_build_phase.files_references.include?(ref)
    target.frameworks_build_phase.add_file_reference(ref, true)
  end
end

# ---------- 5) Other Linker Flags ----------
target.build_configurations.each do |cfg|
  cur = cfg.build_settings['OTHER_LDFLAGS']
  cur = [cur] if cur.is_a?(String)
  cur ||= ['$(inherited)']
  LD_FLAGS.each { |f| cur << f unless cur.include?(f) }
  cfg.build_settings['OTHER_LDFLAGS'] = cur
end

project.save
puts '============ 微信 OpenSDK 集成完成 ============'
puts "  1) 已链接并 Embed & Sign: #{FW_NAME}"
puts "  2) 系统框架: #{SYS_FW.join(', ')}"
puts "  3) Other Linker Flags: #{LD_FLAGS.join(' ')}"
puts '  （重复运行本脚本结果一致，不会重复添加）'
