# はじめてのDroonga

subtitle
:   Droongaの簡単な紹介と、
    Groongaからの移行手順

author
:   結城洋志

institution
:   株式会社クリアコード

theme
:   groonga

# 要旨

「自作のアプリケーションを
GroongaからDroongaへ
今すぐ移行できるのか？」
にお答えします


# アジェンダ

 * Droongaとは？
   * Droongaの何が嬉しい？
   * Droongaの何が嬉しくない？
 * デモ



# Groongaの困った所

 * 分散が流行ってる
 * Groongaは分散処理に
   対応していない


# Droongaとは

*D*istributed G*roonga*
＝分散Groonga

# サーバ構成の違い

![](images/groonga-vs-droonga.png){:relative_height='95'}

# Groonga互換

![](images/groonga-vs-droonga-compatible-http.png){:relative_height='95'}

# Groonga互換

 * 今までと同じ感覚で使える
 * Groongaベースの
   既存のアプリケーションを
   最小の工数で分散対応できる

# データベースを分散

 * *レプリケーション*
   * 現在の開発はここに注力
 * *パーティショニング*
   * 現在は部分的に対応（これから改善）

# Groonga→Droonga

今現在得られるメリット

 * *レプリケーションできる*ようになる
 * ノードを*簡単に追加・削除*できる

# レプリケーション無しだと(1)

![](images/service-groonga.png "単一のGroongaサーバに
サービスが依存"){:relative_height='90'}

# レプリケーション無しだと(1)

![](images/service-groonga-dead-1.png "Groongaが死ぬと……"){:relative_height='90'}

# レプリケーション無しだと(1)

![](images/service-groonga-dead-2.png "サービスも道連れになる"){:relative_height='90'}

# レプリケーション無しだと(2)

![](images/service-groonga-overload.png "負荷が増大すると……"){:relative_height='90'}

# レプリケーション無しだと(2)

![](images/service-groonga-overload-2.png "サービスレベルが落ちる"){:relative_height='90'}

# レプリケーション有りだと(1)

![](images/replication-write.png "データが自動的に複製される"){:relative_height='90'}

# レプリケーション有りだと(1)

![](images/replication-read-dead.png "耐障害性が高くなる"){:relative_height='90'}

# レプリケーション有りだと(1)

![](images/service-droonga.png "単一のサーバに依存しなくなる"){:relative_height='90'}

# レプリケーション有りだと(1)

![](images/service-droonga-dead.png "障害があってもサービスを
提供し続けられる"){:relative_height='90'}

# レプリケーション有りだと(2)

![](images/replication-read.png "負荷が分散される"){:relative_height='90'}

# レプリケーション有りだと(2)

![](images/service-droonga-overload.png "負荷の増大に対応しやすい"){:relative_height='90'}


# クラスタ構成の変更

付属のコマンドラインユーティリティを使用

 * droonga-engine-join
 * droonga-engine-unjoin

# ノードの追加

    % droonga-engine-join --host=cccc --replica-source-host=bbbb

![](images/join.png){:relative_height='100'}

# ノードの切り離し

    % droonga-engine-unjoin --host=cccc

![](images/unjoin.png){:relative_height='100'}


## パーティショニング

![](images/partition-write.png){:relative_height='90'}

## パーティショニング

![](images/partition-read.png){:relative_height='90'}

## パーティショニング

![](images/partition-and-replication.png){:relative_height='90'}

## パーティショニング

![](images/partition-and-replication-actual.png){:relative_height='90'}




# Groonga→Droonga

今現在あるデメリット

 * *レイテンシーが低下*する
 * *Groonga非互換*の部分が
   まだある


# Groongaとの性能比較

（ここにグラフ）

## オーバーヘッド

 * オーバーヘッドがある（レイテンシーが落ちる）
 * Groongaで単一サーバでさばききれる程度のリクエストに対しては、性能面でのメリットはない。
 * 耐障害性の高さ、アクセスの増加への対応のしやすさとのトレードオフ。


# 現時点での互換性

 * スキーマ変更
 * load, delete
 * select

それ以外は未対応（今後の課題）

## 未対応の機能

 * GQTPは喋れない
 * 未対応のコマンドや、コマンドによっては未対応のオプションがある
   * 対応コマンドの一覧（主要なコマンドから実装している）
 * ダッシュボードがまだ無い（Groongaの管理画面はちょっと動く）
 * サジェストもまだ対応していない
 * 監視機能もまだできていない

# とはいえ

![](images/groonga-vs-droonga-compatible-http.png "使用中の機能の範囲次第では
今すぐにでもDroongaに移行できる！"){:relative_height="90"}



# デモ

 * Groongaベースの
   アプリケーションを作成
 * バックエンドをDroongaに移行
   * Droongaクラスタを構築
   * データを移行
   * アプリケーションの接続先変更


# 改善にご協力を！

*様々な条件でのベンチマーク結果*

 * できればGroongaでの
   ベンチマーク結果も添えて
 * 開発チームで認識できていない
   ボトルネックを明らかにしたい

# 改善にご協力を！

実際のWebアプリケーションからの
*使い勝手レポート*

 * 互換性向上の作業の
   優先順位付けの参考にしたい

# 改善にご協力を！

フィードバックは
[droonga-engineのissue tracker](https://github.com/droonga/droonga-engine/issues)
もしくは
groonga-dev ML
までお寄せ下さい

## 参考：Droonga以外の分散Groonga

 * MySQL/MariaDB + Mroonga + Spider
 * 自前で頑張る
   （[Yappoさんによる事例](http://blog.yappo.jp/yappo/archives/000843.html)）

