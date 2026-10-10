#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把「手动创建的本地原生插件」类名注入 iOS 生成的 capacitor.config.json 的 packageClassList。

背景：Capacitor 的 iOS 自动注册只认 packageClassList —— 该列表由 `npx cap sync ios`
扫描 node_modules 里的 npm 插件自动生成。我们的微信登录插件 WechatAuthPlugin 是
直接放在 App target 里的本地 Swift 插件（不是 npm 包），cap sync 不会把它写进列表，
导致虽然被编译进 App，运行时却报 “"WechatAuth" plugin is not implemented on ios”。

本脚本在 cap sync 之后运行，把本地插件类名补入 packageClassList。幂等，可重复执行。
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TARGET = os.path.join(HERE, 'ios', 'App', 'App', 'capacitor.config.json')

# 本地（非 npm）原生插件的 Objective-C 运行时类名
LOCAL_PLUGIN_CLASSES = ['WechatAuthPlugin']

if not os.path.exists(TARGET):
    sys.exit('未找到 %s，请先运行：npx cap sync ios' % TARGET)

with open(TARGET, encoding='utf-8') as f:
    data = json.load(f)

class_list = list(data.get('packageClassList') or [])
added = []
for cls in LOCAL_PLUGIN_CLASSES:
    if cls not in class_list:
        class_list.append(cls)
        added.append(cls)

data['packageClassList'] = class_list

with open(TARGET, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print('packageClassList =', class_list)
print('本次补入:', added if added else '无（本地插件均已在列表）')
