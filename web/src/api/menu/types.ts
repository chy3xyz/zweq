export interface WechatMenuButton {
  name: string;
  type?: 'click' | 'view' | 'miniprogram' | 'media_id' | 'view_limited' | 'article_id' | 'article_view_limited' | 'scancode_push' | 'scancode_waitmsg' | 'pic_sysphoto' | 'pic_photo_or_album' | 'pic_weixin' | 'location_select';
  key?: string;
  url?: string;
  media_id?: string;
  appid?: string;
  pagepath?: string;
  article_id?: string;
  sub_button?: WechatMenuButton[];
}

export interface WechatMenu {
  menu_json: string;
}

export interface SaveMenuRequest {
  menu_json: string;
}
