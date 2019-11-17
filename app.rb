
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
  @flash = session[:flash]
  session[:flash] = nil
  erb :login
end

post '/login' do
  @res = client.exec_params('select * from users where user_name=$1 and user_pass=$2', [params[:name], params[:pass]]).first

  session[:user_id] = @res['id'] unless @res.nil?

  unless session[:user_id].nil?
    session[:flash] = "<p class='animated fadeInDown' id = 'flash_info' style='
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
    session[:flash] = "<p class='animated fadeInDown' id = 'flash_info' style='
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

get '/logout' do
  session[:user_id] = nil
  redirect '/login'
end

get '/signup' do
  @flash = session[:flash]
  session[:flash] = nil
  erb :signup
end

post '/signup' do
  name = params[:name]
  pass = params[:pass]

  @res = client.exec_params("select * from users where user_name = $1", [name]).first

  unless @res.nil?
    session[:flash] = "<p class='animated fadeInDown' id = 'flash_info' style='
      height: 40px;
      background-color: rgba(32, 163, 65, 0.83);
      padding: 8px 15px;
      margin: 0 15px 25px 15px;
      border-radius: 5px;
      color: white;
      font-size: 1.7em;
      font-weight: solid;
    '>通知： 入力された名前は、既に使用されています。</p>"
    redirect '/signup'
  else
    session[:user_id] = client.exec_params('insert into users(user_name, user_pass, user_profile) values($1, $2, $3) returning id;', [name, pass, nil])['id'].to_i

    FileUtils.mv(params[:new_icon_img][:tempfile], "./public/user_icon/#{session[:user_id]}_icon.jpg")
    FileUtils.mv(params[:new_back_img][:tempfile], "./public/user_back/#{session[:user_id]}_back.jpg")

    session[:flash] = "<p class='animated fadeInDown' id = 'flash_info' style='
      height: 40px;
      background-color: rgba(48, 172, 199, 0.83);
      padding: 8px 15px;
      margin: 0 15px 25px 15px;
      border-radius: 5px;
      color: white;
      font-size: 1.7em;
      font-weight: solid;
    '>成功： 登録が無事処理されました。続けてログインして下さい。</p>"
    redirect '/login'
  end
end
