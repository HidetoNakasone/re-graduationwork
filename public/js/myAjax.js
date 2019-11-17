$(function(){
$('#profile_ajax').click(function(){
  // button(id = go_comment) の 値を取得している？？？？
  var go_comment = $('#go_comment').val();
  $.ajax({

    // 一度、app.rbのルーティングへ飛ぶ。
    type: 'GET',
    url: '/mypage/ajax/' + go_comment,
    dataType: 'json',

    // app.rb からのデータを ブラウザ へ返す。
    success: function(json) {
      $('#result').append(
        "<p id = 'account_comment'>次回からのイメージ： ↓<br>" + json.comment + '</p>'
      );
    },

    error: function() {
      $('#result').append(
        "<p id = 'account_comment'>" + '入力後にボタンを押して下さい。' + '</p>'
      );
    }

  });
});
});

$(function(){
$('.iine_ajax').click(function(){
  var nya_msg = $('.nya_msg').val();
  var want = $('.39').val();

  $.ajax({

    // 一度、app.rbのルーティングへ飛ぶ。
    type: 'GET',
    url: '/iine/ajax/' + nya_msg,
    dataType: 'json',

    // app.rb からのデータを ブラウザ へ返す。
    success: function(json) {
      $('.result').append(
        // "hello" + json.text
        "hello" + want
      );
    },

    error: function() {
      $('.result').append(
        "なんかエラーしたよ。"
      );
    }

  });


});
});
