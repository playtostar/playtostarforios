#!/bin/bash
# ============================================================
# 微信 OpenSDK 集成 · Mac 包装脚本
# 正常情况下工程已集成好 xcframework，无需运行本脚本；
# 仅当 App.xcodeproj 被重置 / 微信相关引用缺失时，用它一键修复。
# 运行：bash setup_wechat.sh   （目录 ios/App）
# ============================================================
set -e
cd "$(dirname "$0")"

# 1) 确保有 ruby（新版 macOS 可能不再自带）
if ! command -v ruby >/dev/null 2>&1; then
  echo "未找到系统 Ruby，尝试通过 Homebrew 安装 ..."
  if ! command -v brew >/dev/null 2>&1; then
    echo "需要先安装 Homebrew： https://brew.sh ，或自行安装 Ruby 后重试。"
    exit 1
  fi
  brew install ruby
  export PATH="$(brew --prefix ruby)/bin:$PATH"
fi

# 2) 确保 xcodeproj gem
if ! ruby -e "require 'xcodeproj'" 2>/dev/null; then
  echo "安装 xcodeproj gem ..."
  if ruby -e 'exit(File.writable?(Gem.default_dir) ? 0 : 1)' 2>/dev/null; then
    gem install xcodeproj --no-document
  else
    sudo gem install xcodeproj --no-document
  fi
fi

# 3) 执行集成（幂等）
ruby setup_wechat.rb
echo "==> 完成。用 Xcode 打开 App.xcodeproj，在 Signing & Capabilities 确认："
echo "    Sign in with Apple、Associated Domains(applinks:playtostar.com) 已勾选。"
