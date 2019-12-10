
require 'sinatra'
require 'sinatra/reloader'
require 'pg'

enable :sessions

def client
  @client ||= PG::connect(
    dbname: 'regra'
  )
end

def login_check
  redirect '/login' if session[:user_id].nil?
end

def dateinfo_converter(dateinfo)
  # ツイートの投稿日時に関して
  unless dateinfo.nil?
    if dateinfo > Time.now - 60
      # 1分 以内
      return "#{(Time.now - dateinfo).floor}秒前"
    elsif dateinfo > Time.now - (60*60)
      # 1時間 以内
      return "#{((Time.now - dateinfo)/(60)).floor}分前"
    elsif dateinfo > Time.now - (24*60*60)
      # 24時間 以内
      return "#{((Time.now - dateinfo)/(60*60)).floor}時間前"
    elsif dateinfo > Time.now - (30*24*60*60)
      # 1月 以内
      return "#{((Time.now - dateinfo)/(24*60*60)).floor}日前"
    elsif dateinfo > Time.now - (365*24*60*60)
      # 1年 以内
      return "#{((Time.now - dateinfo)/(30*24*60*60)).floor}ヶ月前"
    else
      # 1年 以上
      return "#{((Time.now - dateinfo)/(365*24*60*60)).floor}年前"
    end
  end
end

get '/top' do
  login_check()

  # 自分についての情報を取得
  @my_user_id = session[:user_id]
  @my_user_name = client.exec_params("select user_name from users where id = $1", [@my_user_id]).first['user_name']

  # 自分とフォローしているユーザーの投稿取得
  @res = client.exec_params("select tweets.*, users.user_name from tweets left outer join users on tweets.creater_id = users.id where creater_id = $1 OR (creater_id IN (select send_id from follows where who_id = $1)) ORDER BY tweets.id DESC;", [@my_user_id]).to_a

  # 日付情報を 見やすい形に変形 した形を再代入させる
  @res.each { |i| i['dateinfo'] = dateinfo_converter(Time.parse(i['dateinfo'])) }

  # 取得した投稿がリツートであれば、その元のツイート内容を取得する
  @res.each do |i|
    unless i['re_sou_id'].nil?
      i['re_sou_tweet'] = client.exec_params('select * from tweets where id = $1', [i['re_sou_id'].to_i]).first
      # 日付情報も上と同じ様に変形を代入
      i['re_sou_tweet']['dateinfo'] = dateinfo_converter(Time.parse(i['re_sou_tweet']['dateinfo']))
    end
  end

  # ログインユーザーが いいね しているtwe_idを取得
  my_iine_lists = []
  client.exec_params('select twe_id from iine where who_id = $1', [@my_user_id]).each { |i| my_iine_lists.push(i['twe_id']) }

  # ログインユーザーが リツイート しているtwe_idを取得
  my_retw_lists = []
  client.exec_params('select retw_id from retw where who_id = $1', [@my_user_id]).each { |i| my_retw_lists.push(i['retw_id']) }

  # 取得した投稿の "総リツイート数・総いいね数・ログイン者がいいねしているか、リツイートしているか" を反映させる
  @res.each do |i|
    target_id = i['id']
    # その投稿がリツートなら、リツート元の投稿に対して いいね・リツート しているか調べる。
    target_id = i['re_sou_id'] unless i['re_sou_id'].nil?
    if my_iine_lists.include?(target_id)
      i['is_iine'] = true
    else
      i['is_iine'] = false
    end
    if my_retw_lists.include?(target_id)
      i['is_retw'] = true
    else
      i['is_retw'] = false
    end
    i['n_iines'] = client.exec_params('select count(*) as n from iine where twe_id = $1', [target_id]).first['n'].to_i
    i['n_retws'] = client.exec_params('select count(*) as n from retw where retw_id = $1', [target_id]).first['n'].to_i
  end

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
  @is_animation = session[:is_animation] || true
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

post '/add_tweet' do
  if params[:go_file].nil? and params[:go_msg] == ""
    session[:flash] = "<p class='animated fadeInDown' id = 'flash_info' style='height: 34px; width: 30%; z-index: 2px; background-color: rgb(37, 165, 221); padding-left: 20px; margin: 6px 35% 10px 35%; border-radius: 5px; color: white; font-size: 1.5em; font-weight: solid;'>Info： データが空でした。</p>
    <style> #header_div { margin-top: -70px; } </style>"
  else
    if params[:go_file]
      file_name = ((0..9).to_a + ("a".."z").to_a + ("A".."Z").to_a).sample(30).join
      FileUtils.mv(params[:go_file][:tempfile], "./public/up_imgs/#{file_name}.jpg")
    else
      file_name = nil
    end

    unless params[:go_msg] == ""
      go_msg = CGI.escapeHTML(params[:go_msg]).gsub(/\r\n|\r|\n/, "<br />")
    else
      go_msg = nil
    end

    client.exec_params("INSERT INTO tweets(creater_id, dateinfo, msg, img_name, re_sou_id) VALUES($1, current_timestamp, $2, $3, NULL);", [session[:user_id], go_msg, file_name])

    session[:flash] = "<p class='animated fadeInDown' id = 'flash_info' style='height: 34px; width: 30%; z-index: 2px; background-color: rgb(37, 165, 221); padding-left: 20px; margin: 6px 35% 10px 35%; border-radius: 5px; color: white; font-size: 1.5em; font-weight: solid;'>完了： 投稿が正常に処理されました。</p>
    <style> #header_div { margin-top: -70px; } </style>"
  end
  redirect '/top'
end

