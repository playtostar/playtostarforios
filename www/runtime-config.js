window.RUNTIME_CONFIG = {
  // API 基础地址：APP/独立套壳必须指向自有后端（空值会回退到设备自身源 https://localhost，导致登录 Network Error）
  API_BASE_URL: 'https://playtostar.com',
  // 微信移动应用 AppID（Android/iOS 登录用，与原生 WechatAuth 插件内一致）
  WECHAT_MOBILE_APPID: 'wxd0ef5d487ac33750',
  // 微信网页应用 AppID（网站扫码登录用）
  WECHAT_WEB_APPID: 'wxd4625536619db733',
  // 微信小程序 AppID（小程序端在其工程内单独配置）
  WECHAT_MINI_APPID: '',
};
