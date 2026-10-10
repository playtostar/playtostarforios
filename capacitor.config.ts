import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.playtostar.app',
  appName: '实况起点',
  webDir: 'www',
  android: {
    // 仅允许 HTTPS，禁止混合内容（图片与接口均为 HTTPS）
    allowMixedContent: false,
  },
  ios: {
    // 允许 WKWebView 整页滚动，保证 iOS 长页面可上下滑动
    scrollEnabled: true,
  },
  plugins: {
    // 深色背景 → 状态栏文字/图标用浅色（白色）；内容延伸到状态栏下方，
    // 按钮位置由 safe-area-inset 控制。Android 15 强制 edge-to-edge，overlays 自动忽略。
    StatusBar: {
      style: 'DARK',
      overlaysWebView: true,
    },
  },
};

export default config;
