
require 'bundler'
Bundler.require

# 開発環境のみ実行 (Heroku環境だと実行しない)
if development?
  require 'sinatra/reloader'
  require 'dotenv'
  Dotenv.load ".env"
end

enable :sessions

def client
  uri = URI.parse(ENV['DATABASE_URL'])
  @client ||= PG::connect(
    host: uri.hostname,
    dbname: uri.path[1..-1],
    user: uri.user,
    port: uri.port,
    password: uri.password
  )
end

# AWS S3 への接続クライアント
def s3
  @s3 ||= Aws::S3::Client.new(
    :region => 'us-east-2',
    :access_key_id => ENV['AWS_S3_ACCESS_KEY_ID'],
    :secret_access_key => ENV['AWS_S3_SECRET_ACCESS_KEY']
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

get '/' do
  redirect '/top'
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
  client.exec_params('select re_sou_id from tweets where creater_id = $1 and re_sou_id is not null', [@my_user_id]).each { |i| my_retw_lists.push(i['re_sou_id']) }

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
    i['n_retws'] = client.exec_params('select count(*) as n from tweets where re_sou_id = $1', [target_id]).first['n'].to_i
  end

  # フォロワー情報： 5人
  @res_follower = client.exec_params("select * from users where id IN (select who_id from follows where send_id = $1) ORDER BY id ASC LIMIT 5;", [@my_user_id]).to_a

  my_follow_lists = []
  client.exec_params('select send_id from follows where who_id = $1', [@my_user_id]).each { |i| my_follow_lists.push(i['send_id']) }

  @res_follower.each do |i|
    if my_follow_lists.include?(i['id'])
      i['is_follow'] = true
    else
      i['is_follow'] = false
    end
  end

  # フォロー情報： 5人
  @res_follow = client.exec_params("select * from users where id IN (select send_id from follows where who_id = $1) ORDER BY id ASC LIMIT 5;", [@my_user_id])

  # フォロー数
  @count_follow = client.exec_params("select count(*) as n from follows where who_id = $1", [@my_user_id]).first['n'].to_i

  # フォロワー数
  @count_follower = client.exec_params("select count(*) as n from follows where send_id = $1", [@my_user_id]).first['n'].to_i

  # ツイート数
  @count_tweet = client.exec_params("select count(*) as n from tweets where creater_id = $1", [@my_user_id]).first['n'].to_i

  client.finish

  @title = 'TOPページ'
  @flash = session[:flash]
  session[:flash] = nil
  # いいね と リツイート登録 の時はアニメーションをオフにしたいので。
  @is_animation = session[:is_animation] || true
  erb :top
end

get '/mypage' do
  redirect "/mypage/#{session[:user_id]}"
end

get '/mypage/' do
  redirect "/mypage/#{session[:user_id]}"
end

get '/mypage/:target_user_id' do
  login_check()

  @target_user_id = params['target_user_id'].to_i

  # 指定されたターゲットユーザーが存在しているか判定し、もし存在して居ないのであればtopへリダイレクト！
  res_target_user_infos = client.exec_params('select user_name, user_profile from users where id = $1', [@target_user_id]).first

  if res_target_user_infos.nil?
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
    '>ユーザーが存在しません。</p>
    <style> #header_div { margin-top: -70px; } </style>"
    client.finish
    redirect '/top'
  end

  @target_user_name = res_target_user_infos['user_name']
  @target_user_profile = res_target_user_infos['user_profile']

  # ログインユーザーについての情報を取得
  @my_user_id = session[:user_id]
  @my_user_name = client.exec_params("select user_name from users where id = $1", [@my_user_id]).first['user_name']

  if @target_user_id == @my_user_id
    @is_same = true

    @page_res_title = "<span style='font-weight: bold; color: rgb(37, 165, 221);'>" + @target_user_name + "</span>"

    # 自分のみ が投稿した ツイートを読み込む
    @res = client.exec_params("select tweets.*, users.user_name from tweets left outer join users on tweets.creater_id = users.id where creater_id = $1 ORDER BY tweets.id DESC;", [@my_user_id]).to_a
  else
    @is_same = false

    @page_res_title = "<span style='font-weight: bold; color: rgb(37, 165, 221);'>" + @target_user_name + "</span>&nbsp;の投稿・<span style='font-weight: bold; color: rgb(37, 165, 221);'>フォローユーザー</span>"

    # そのターゲットユーザーの投稿と、その人がフォローしているアカウントの投稿一覧を取得
    @res = client.exec_params("select tweets.*, users.user_name from tweets left outer join users on tweets.creater_id = users.id where creater_id = $1 OR (creater_id IN (select send_id from follows where who_id = $1)) ORDER BY tweets.id DESC;", [@target_user_id]).to_a

    # ログインしているユーザーが、そのユーザーをフォローしているか
    @is_follow = !(client.exec_params('select id from follows where who_id = $1 and send_id = $2', [@my_user_id, @target_user_id]).first.nil?)
  end

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
  client.exec_params('select re_sou_id from tweets where creater_id = $1 and re_sou_id is not null', [@my_user_id]).each { |i| my_retw_lists.push(i['re_sou_id']) }

  # 取得した投稿の "総リツイート数・総いいね数・ログインユーザーがいいねしているか、リツイートしているか" を反映させる
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
    i['n_retws'] = client.exec_params('select count(*) as n from tweets where re_sou_id = $1', [target_id]).first['n'].to_i
  end

  # そのターゲットユーザーのフォロワー情報
  @res_follower = client.exec_params("select * from users where id IN (select who_id from follows where send_id = $1) ORDER BY id ASC;", [@target_user_id]).to_a

  my_user_follow_lists = []
  client.exec_params('select send_id from follows where who_id = $1', [@my_user_id]).each { |i| my_user_follow_lists.push(i['send_id']) }

  @res_follower.each do |i|
    if my_user_follow_lists.include?(i['id'])
      i['is_follow'] = true
    else
      i['is_follow'] = false
    end
  end

  # フォロー情報
  @res_follow = client.exec_params("select * from users where id IN (select send_id from follows where who_id = $1) ORDER BY id ASC;", [@target_user_id])

  # フォロー数
  @count_follow = client.exec_params("select count(*) as n from follows where who_id = $1", [@target_user_id]).first['n'].to_i

  # フォロワー数
  @count_follower = client.exec_params("select count(*) as n from follows where send_id = $1", [@target_user_id]).first['n'].to_i

  # ツイート数
  @count_tweet = client.exec_params("select count(*) as n from tweets where creater_id = $1", [@target_user_id]).first['n'].to_i

  # いいね数
  @count_iine = client.exec_params("select count(*) as n from iine where who_id = $1", [@target_user_id]).first['n'].to_i

  client.finish

  @title = "#{@target_user_name}さんのページ"
  @flash = session[:flash]
  session[:flash] = nil
  # いいね と リツイート登録 の時はアニメーションをオフにしたいので。
  @is_animation = session[:is_animation] || true
  erb :mypage
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

  session[:user_id] = @res['id'].to_i unless @res.nil?

  client.finish

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
    client.finish
    redirect '/signup'
  else
    session[:user_id] = client.exec_params('insert into users(user_name, user_pass, user_profile) values($1, $2, $3) returning id;', [name, pass, nil]).first['id'].to_i

    # FileUtils.mv(params[:back_img][:tempfile], "./public/user_icon/#{session[:user_id]}_icon.jpg")
    # FileUtils.mv(params[:back_img][:tempfile], "./public/user_back/#{session[:user_id]}_back.jpg")

    object_key = "user_icon/#{session[:user_id]}_icon.jpg"
    # 保存処理
    s3.put_object(
      bucket: ENV['AWS_S3_BUCKET'],
      key: object_key,
      body: params[:icon_img][:tempfile],
      content_type: "image/jpegput",
      metadata: {}
    )
    # アクセスを公開に設定する
    s3.put_object_acl({
      acl: "public-read",
      bucket: ENV['AWS_S3_BUCKET'],
      key: object_key,
    })

    object_key = "user_back/#{session[:user_id]}_back.jpg"
    # 保存処理
    s3.put_object(
      bucket: ENV['AWS_S3_BUCKET'],
      key: object_key,
      body: params[:back_img][:tempfile],
      content_type: "image/jpegput",
      metadata: {}
    )
    # アクセスを公開に設定する
    s3.put_object_acl({
      acl: "public-read",
      bucket: ENV['AWS_S3_BUCKET'],
      key: object_key,
    })

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
    client.finish
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
      # FileUtils.mv(params[:go_file][:tempfile], "./public/up_imgs/#{file_name}.jpg")
      object_key = "up_imgs/#{file_name}.jpg"
      # 保存処理
      s3.put_object(
        bucket: ENV['AWS_S3_BUCKET'],
        key: object_key,
        body: params[:go_file][:tempfile],
        content_type: "image/jpegput",
        metadata: {}
      )
      # アクセスを公開に設定する
      s3.put_object_acl({
        acl: "public-read",
        bucket: ENV['AWS_S3_BUCKET'],
        key: object_key,
      })
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
  client.finish
  redirect '/top'
end

post '/foll_system' do
  login_check()

  # 解除処理
  client.exec_params('delete from follows where who_id = $1 and send_id = $2', [session[:user_id], params[:now_follow_id].to_i]) if params[:delete_follow] == "フォロー中"

  # ログインユーザーが自分自身をフォローできない様にする
  unless params[:now_unfollower_id].to_i == session[:user_id]
    # 追加処理
    client.exec_params('insert into follows(who_id, send_id) values($1, $2)', [session[:user_id], params[:now_unfollower_id].to_i]) if params[:add_follow] == "フォローする"
  end
  client.finish
  redirect params[:from_url]
end

post '/iine_system' do
  login_check()

  # 登録処理
  client.exec_params('insert into iine(who_id, twe_id) values($1, $2)', [session[:user_id], params[:twe_id].to_i]) if params[:iine_on]

  # 解除処理
  client.exec_params('delete from iine where who_id = $1 and twe_id = $2', [session[:user_id], params[:twe_id].to_i]) if params[:iine_off]

  client.finish

  # このルーティングを通った場合、animatedのアニメーションをoff
  session[:is_animation] = false

  # === redirect で元の投稿の表示部分へ戻そうとしている。 ===
  # 上の投稿が画像なら、それを表示させる。
  if params[:pre_img_is] == "true"
    # ただ、自分が画像持っているなら、自分を表示。
    if params[:my_img_is] == "true"
      redirect "#{params[:from_url]}#res_num_#{params[:res_num].to_i - 0}"
    else
      redirect "#{params[:from_url]}#res_num_#{params[:res_num].to_i - 1}"
    end
  else
    # 上が画像でない。なら、2 か 1 つ前の投稿を表示させる。 迷っている。
    redirect "#{params[:from_url]}#res_num_#{params[:res_num].to_i - 2}"
  end
end

post '/retw_system' do
  login_check()

  # 登録処理
  if params[:retw_on]
    client.exec_params('insert into tweets(creater_id, dateinfo, msg, img_name, re_sou_id) values($1, current_timestamp, NULL, NULL, $2)', [session[:user_id], params[:twe_id].to_i])
  end

  client.finish

  # このルーティングを通った場合、animatedのアニメーションをoff
  session[:is_animation] = false

  # === redirect で元の投稿の表示部分へ戻そうとしている。 ===
  # 上の投稿が画像なら、それを表示させる。
  if params[:pre_img_is] == "true"
    # ただ、自分が画像持っているなら、自分を表示。
    if params[:my_img_is] == "true"
      redirect "#{params[:from_url]}#res_num_#{params[:res_num].to_i - 0}"
    else
      redirect "#{params[:from_url]}#res_num_#{params[:res_num].to_i - 1}"
    end
  else
    # 上が画像でない。なら、2 か 1 つ前の投稿を表示させる。 迷っている。
    redirect "#{params[:from_url]}#res_num_#{params[:res_num].to_i - 2}"
  end
end

post '/edit_img_back' do
  login_check()

  # FileUtils.mv(params[:go_img_back][:tempfile], "./public/user_back/#{session[:user_id]}_back.jpg")
  object_key = "user_back/#{session[:user_id]}_back.jpg"
  # 保存処理
  s3.put_object(
    bucket: ENV['AWS_S3_BUCKET'],
    key: object_key,
    body: params[:go_img_back][:tempfile],
    content_type: "image/jpegput",
    metadata: {}
  )
  # アクセスを公開に設定する
  s3.put_object_acl({
    acl: "public-read",
    bucket: ENV['AWS_S3_BUCKET'],
    key: object_key,
  })
  redirect params[:from_url]
end

post '/edit_img_icon' do
  login_check()

  # FileUtils.mv(params[:go_img_icon][:tempfile], "./public/user_icon/#{session[:user_id]}_icon.jpg")
  object_key = "user_icon/#{session[:user_id]}_icon.jpg"
  # 保存処理
  s3.put_object(
    bucket: ENV['AWS_S3_BUCKET'],
    key: object_key,
    body: params[:go_img_icon][:tempfile],
    content_type: "image/jpegput",
    metadata: {}
  )
  # アクセスを公開に設定する
  s3.put_object_acl({
    acl: "public-read",
    bucket: ENV['AWS_S3_BUCKET'],
    key: object_key,
  })
  redirect params[:from_url]
end

post '/edit_user_profile' do
  login_check()

  client.query('update users set user_profile = $1 where id = $2', [params[:new_user_profile], session[:user_id]])
  client.finish
  redirect '/mypage'
end
