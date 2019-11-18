
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
  redirect '/login' if session[:user_id].nil?
end

get '/top' do
  login_check()

  # 自分についての情報を取得
  @my_user_id = session[:user_id]
  @my_user_name = client.exec_params("select user_name from users where id = $1", [@my_user_id]).first['user_name']

  # 自分とフォローしているユーザーの投稿取得
  @res = client.exec_params("select * from tweets where creater_id = $1 OR (creater_id IN (select send_id from follows where who_id = $1)) ORDER BY id DESC", [@my_user_id])

  # フォロワー情報
  @res_follower = client.exec_params("select * from users where id IN (select who_id from follows where send_id = $1) ORDER BY id ASC LIMIT 5;", [@my_user_id]).to_a

  my_follow_lists = []
  client.exec_params('select send_id from follows where who_id = $1', [1]).each { |i| my_follow_lists.push(i['send_id']) }

  @res_follower.each do |i|
    if my_follow_lists.include?(i['id'])
      i['is_follow'] = true
    else
      i['is_follow'] = false
    end
  end

  # フォロー情報
  @res_follow = client.exec_params("select * from users where id IN (select send_id from follows where who_id = $1) ORDER BY id ASC LIMIT 5;", [@my_user_id])

  # フォロー数
  @count_follow = client.exec_params("select count(who_id = $1 or null) as n from follows", [@my_user_id]).first['n'].to_i

  # フォロワー数
  @count_follower = client.exec_params("select count(send_id = $1 or null) as n from follows", [@my_user_id]).first['n'].to_i

  # ツイート数
  @count_tweet = client.exec_params("select count(creater_id = $1 or null) as n from tweets", [@my_user_id]).first['n'].to_i

  @title = 'TOPページ'
  @flash = session[:flash]
  session[:flash] = nil
  # いいね と リツイート登録 の時はアニメーションをオフにしたいので。
  @is_animation = session[:is_animation]
  erb :top
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
    session[:user_id] = client.exec_params('insert into users(user_name, user_pass, user_profile) values($1, $2, $3) returning id;', [name, pass, nil]).first['id'].to_i

    FileUtils.mv(params[:icon_img][:tempfile], "./public/user_icon/#{session[:user_id]}_icon.jpg")
    FileUtils.mv(params[:back_img][:tempfile], "./public/user_back/#{session[:user_id]}_back.jpg")

    session[:flash] = "<p class='animated fadeInDown' id = 'flash_info' style='
      height: 40px;
      background-color: rgba(48, 172, 199, 0.83);
      padding: 8px 15px;
      margin: 0 15px 25px 15px;
      border-radius: 5px;
      color: white;
      font-size: 1.7em;
      font-weight: solid;
    '>成功： 登録が無事処理されました。ようこそ。</p>"
    redirect '/login'
  end
end
