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
    // 禁用 WKWebView 整页橡皮筋滚动（页面内部容器各自滚动），与安卓体验一致
    scrollEnabled: false,
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
