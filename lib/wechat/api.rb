require 'erb'

require 'wechat/client'
require 'wechat/access_token'
require 'wechat/jsapi_ticket'

class Wechat::Api
  attr_reader :access_token, :client, :jsapi_ticket

  API_BASE = "https://api.weixin.qq.com/cgi-bin/"
  FILE_BASE = "http://file.api.weixin.qq.com/cgi-bin/"
  MP_BASE = "https://mp.weixin.qq.com/cgi-bin/"
  OAUTH2_BASE = 'https://api.weixin.qq.com/sns/oauth2/'

  def initialize(appid, secret, token_file, jsapi_ticket_file = '/var/tmp/wechat_jsapi_ticket')
    @client = Wechat::Client.new(API_BASE)
    @access_token = Wechat::AccessToken.new(@client, appid, secret, token_file)
    @jsapi_ticket = Wechat::JsapiTicket.new(@client, @access_token, jsapi_ticket_file)
  end

  def users(nextid = nil)
    params = { params: { next_openid: nextid } } if nextid.present?
    get('user/get', params || {})
  end

  def user openid, lang = 'en'
    get("user/info", params:{openid: openid, lang: lang})
  end

  def menu
    get('menu/get')
  end

  def menu_delete
    get('menu/delete')
  end

  def menu_create(menu)
    # 微信不接受7bit escaped json(eg \uxxxx), 中文必须UTF-8编码, 这可能是个安全漏洞
    post('menu/create', JSON.generate(menu))
  end

  def media(media_id)
    get 'media/get', params: { media_id: media_id }, base: FILE_BASE, as: :file
  end

  def media_create(type, file)
    post 'media/upload', { upload: { media: file } }, params: { type: type }, base: FILE_BASE
  end

  def custom_message_send(message)
    post 'message/custom/send', message.to_json, content_type: :json
  end

  def template_message_send message
    post "message/template/send", message.to_json, content_type: :json
  end

  def qrcode_create_scene scene_id, expire_seconds = 604800
    data = {expire_seconds: expire_seconds,
            action_name: "QR_SCENE",
            action_info: {scene: {scene_id: scene_id}}}
    post "qrcode/create", data.to_json, content_type: :json
  end

  def qrcode_create_limit_scene scene_id
    data = {action_name: "QR_LIMIT_SCENE",
            action_info: {scene: {scene_id: scene_id}}}
    post "qrcode/create", data.to_json, content_type: :json
  end

  def qrcode_create_limit_str_scene scene_str
    data = {action_name: "QR_LIMIT_STR_SCENE",
            action_info: {scene: {scene_str: scene_str}}}
    post "qrcode/create", data.to_json, content_type: :json
  end

  def qrcode_url ticket
    "#{MP_BASE}showqrcode?ticket=#{ERB::Util.url_encode(ticket)}"
  end

  # http://mp.weixin.qq.com/wiki/17/c0f37d5704f0b64713d5d2c37b468d75.html
  # 第二步：通过code换取网页授权access_token
  def web_access_token(code)
    params = {
      appid: access_token.appid,
      secret: access_token.secret,
      code: code,
      grant_type: 'authorization_code'
    }
    get 'access_token', params: params, base: OAUTH2_BASE
  end

  protected

  def get(path, headers = {})
    with_access_token(headers[:params]) { |params| client.get path, headers.merge(params: params) }
  end

  def post(path, payload, headers = {})
    with_access_token(headers[:params]) { |params| client.post path, payload, headers.merge(params: params) }
  end

  def with_access_token(params = {}, tries = 2)
    params ||= {}
    yield(params.merge(access_token: access_token.token))
  rescue Wechat::AccessTokenExpiredError
    access_token.refresh
    retry unless (tries -= 1).zero?
  end
end
