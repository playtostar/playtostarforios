window.RUNTIME_CONFIG = {
  // API 基础地址：APP/独立套壳必须指向自有后端（空值会回退到设备自身源 https://localhost，导致登录 Network Error）
  API_BASE_URL: 'https://playtostar.com',
  // 微信移动应用 AppID（Android/iOS 登录用，与原生 WechatAuth 插件内一致）
  WECHAT_MOBILE_APPID: 'wxd0ef5d487ac33750',
  // 微信网页应用 AppID（网站扫码登录用）
  WECHAT_WEB_APPID: 'wxd4625536619db733',
  // 微信小程序 AppID（小程序端在其工程内单独配置）
  WECHAT_MINI_APPID: '',
  // 网页 Sign in with Apple 的 Services ID（Apple Developer 后台注册；留空则网页不显示 Apple 登录按钮）
  APPLE_WEB_CLIENT_ID: 'com.playtostar.web',
  // 网页端第三方社交分享平台 App Key（仅浏览器环境使用，原生 App 内不使用该值）
  //   留空：分享入口照常可用，来源显示为该平台默认值；
  //   填入：平台审核通过后把 Key 粘到这里即生效，无需重新构建前端。
  WEB_SHARE_APP_KEY: '',
};
