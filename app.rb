
require 'sinatra'
require 'sinatra/reloader'
require 'pg'

enable :sessions

def client
  PG::connect(
    dbname: 'regra'
  )
end

def login_check
  redirect '/login' unless session[:user_id].nil?
end

get '/login' do
  redirect '/top' unless session[:user_id].nil?
  @title = 'ログイン'
  @flask = session[:flask]
  session[:flask] = nil
  erb :login
end

post '/login' do
# === 入された名前とパスワードがあっているのか判定。 ===
  @res = client.exec_params('select * from users where user_name=$1 and user_pass=$2', [params[:name], params[:pass]]).first

  session[:user_id] = @res['id'] unless @res.nil?

  # === パスワードがあっていないか、そもそも該当する名前のレコードが存在しない場合はlogin_statusがfalseのまま。 ===
  unless session[:user_id].nil?
    session[:flask] = "<p class='animated fadeInDown' id = 'flash_info' style='
      height: 34px;
      width: 30%;
      z-index: 2px;

      background-color: rgb(37, 165, 221);
      padding-left: 20px;

      margin: 6px 35% 10px 35%;
      border-radius: 5px;
      color: white;
      font-size: 1.5em;
      font-weight: solid;
      text-align: center;
    '>ようこそ。</p>
      <style> #header_div { margin-top: -70px; } </style>"
    redirect '/top'
  else
    session[:flask] = "<p class='animated fadeInDown' id = 'flash_info' style='
      height: 40px;
      background-color: rgba(221, 145, 14, 0.71);
      padding: 8px 15px;
      margin: 0 15px 25px 15px;
      border-radius: 5px;
      color: white;
      font-size: 1.7em;
      font-weight: solid;
    '>失敗：入力された情報に不備がありました。</p>"
    redirect '/login'
  end
end

