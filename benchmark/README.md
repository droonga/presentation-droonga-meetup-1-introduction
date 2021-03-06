# Groongaとの比較のベンチマーク取得手順

## 前提

 * 192.168.200.254, 192.168.200.3, 192.168.200.4の3台のコンピュータがあると仮定し、これらをDroongaクラスタにする。
 * 比較用としてGroongaを192.168.200.254にインストールする。
 * ベンチマークのクライアントは、192.168.200.2で実行する。

ネットワーク構成と各マシンの役割は以下の通り。

    (internet)
       |
    [192.168.200.254] router, groonga, droonga-1
       |
     [hub]
       |
       +-[192.168.200.3] droonga-2
       |
       +-[192.168.200.4] droonga-3
       |
       +-[192.168.200.2] benchmark client

 * 192.168.200.254
   * OS: Ubuntu 14.04LTS
   * CPU: Intel Core i5 M460 2.53GHz
   * Memory: 8GB
 * 192.168.200.3
   * OS: Ubuntu 14.04LTS
   * CPU: Intel Core i5 650 3.20GHz
   * Memory: 6GB
 * 192.168.200.4
   * OS: Ubuntu 14.04LTS
   * CPU: Intel Core i5 650 3.20GHz
   * Memory: 8GB

## 準備

### worker数の決定

worker数は、CPUの個数に合わせる。これは以下の方法で調べられる。

    % cat /proc/cpuinfo | grep processor | wc -l

### データベースサイズの決定

GroongaもDroongaも原則として、性能を発揮できるデータベースの最大サイズは、コンピュータの物理的なメモリ搭載量が上限となる。
例えば8GBのメモリを搭載したコンピュータであれば、データベースは8GBまでのサイズに収まることが望ましい。
（それ以上大きなサイズになると、性能が劣化してくる。）
Droongaの場合も、worker数とデータベースの最大サイズには関係はない。

上記の検証環境では、ノードのうち2台が8GB、1台が6GBのメモリを積んでいる。
なので、純粋な性能比較のためのベンチマークとしては、最大で6GB程度のデータベースサイズに留める必要がある。

### データの準備

Wikipediaのデータを取得し、Groongaのダンプファイルに変換する。

    % cd ~/
    % git clone https://github.com/droonga/wikipedia-search.git
    % cd wikipedia-search
    % bundle install
    % time rake data:convert:groonga:ja

既定の状態では、Wikipedia日本語版の全ページのうち先頭5000件、各ページは先頭から最大1000文字までのみ変換される。
それ以上の件数を変換するには、以下の箇所で「--max-n-*」を指定しているコマンドラインオプションを変更する。
（正しいやり方が分かり次第、この説明を更新する。）

https://github.com/droonga/wikipedia-search/blob/master/lib/wikipedia-search/task.rb#L79

件数とデータベースサイズは残念ながら比例関係にない。
以下は、実際の変換結果。

 * 184万件のページ全件をロードすると、データベースは17GiB程度になった。
   （Groongaへのロードには10時間程度を要した）
 * 15万件のページをロードすると、データベースは3GiB程度になった。
   （変換には12分程度、Groongaへのロードには24分程度を要した）
 * 7万5千件のページをロードすると、データベースは1.9GiB程度になった。
   （変換には7分程度、Groongaへのロードには12分程度を要した）
 * 30万件のページを各ページごとに最大1000文字までロードすると、データベースは1.1GiB程度になった。
   （変換には17分程度、Groongaへのロードには6分程度を要した）
 * 150万件のページを各ページごとに最大1000文字までロードすると、データベースは4.3GiB程度になった。
   （変換には53分程度、Groongaへのロードには64分程度を要した）

今回は以下の2パターンでベンチマークを行った。

 * 30万件のページを各ページごとに最大1000文字まで変換したデータに基づく1.1GiBのデータベース。
 * 150万件のページを各ページごとに最大1000文字まで変換したデータに基づく4.3GiBのデータベース。


## Groongaのセットアップ

192.168.200.254でのみ行う。

### インストール

    % sudo apt-get -y install software-properties-common
    % sudo add-apt-repository -y universe
    % sudo add-apt-repository -y ppa:groonga/ppa
    % sudo apt-get update
    % sudo apt-get -y install groonga

### データベースの用意

    % rm -rf $HOME/groonga/db/
    % mkdir -p $HOME/groonga/db/
    % groonga -n $HOME/groonga/db/db quit
    % time (cat ~/wikipedia-search/config/groonga/schema.grn | groonga $HOME/groonga/db/db)
    % time (cat ~/wikipedia-search/config/groonga/indexes.grn | groonga $HOME/groonga/db/db)
    % time (cat ~/wikipedia-search/data/groonga/ja-pages.grn | groonga $HOME/groonga/db/db)


## Droongaクラスタのセットアップ

192.168.200.254, 192.168.200.3, 192.168.200.4で行う。

### インストール

    (on 192.168.200.254, 192.168.200.3, 192.168.200.4)
    % sudo apt-get update
    % sudo apt-get -y upgrade
    % sudo apt-get install -y ruby ruby-dev build-essential nodejs nodejs-legacy npm
    % sudo gem install droonga-engine grn2drn drnbench
    % sudo npm install -g droonga-http-server
    % rm -rf ~/droonga/000 ~/droonga/state
    % mkdir ~/droonga
    % droonga-engine-catalog-generate \
        --hosts=192.168.200.254,192.168.200.3,192.168.200.4 \
        --n-workers=$(cat /proc/cpuinfo | grep processor | wc -l) \
        --output=~/droonga/catalog.json


### サーバの起動

    (on 192.168.200.254)
    % export host=192.168.200.254
    % export DROONGA_BASE_DIR=$HOME/droonga
    % droonga-engine \
        --host=$host \
        --log-file=$DROONGA_BASE_DIR/droonga-engine.log \
        --daemon \
        --pid-file=$DROONGA_BASE_DIR/droonga-engine.pid
    % droonga-http-server \
        --port=10042 \
        --receive-host-name=$host \
        --droonga-engine-host-name=$host \
        --environment=production \
        --daemon \
        --pid-file=$DROONGA_BASE_DIR/droonga-http-server.pid

    (on 192.168.200.3)
    % export host=192.168.200.3
    ...

    (on 192.168.200.4)
    % export host=192.168.200.4
    ...

### データベースの用意

ダンプからデータベースの内容を用意する。

droonga-sendを使うが、スキーマ定義の時は宛先は1ノードだけにする。
（複数ノードにリクエストを分散すると、スキーマ定義が期待通りに行われないため。
データ投入の時は、負荷分散のため、宛先は3ノードに分散してもよい。

なお、あまりに高速にメッセージを送りすぎると、受け側の処理能力が飽和してジョブキューでメモリを食い潰してしまう。
そのため、処理能力を超えないように`--messages-per-second`オプションで流量を絞る必要がある。
どこまでの流量を受け入れられるかはコンピュータの性能に依存するが、ここでは毎秒50件としている。
流量を絞ると、移行に最短でどれだけの時間がかかるかを計算できる。データが30万件で毎秒50件なら、約1.7時間は最低でもかかる。

    % time (cat ~/wikipedia-search/config/groonga/schema.grn | grn2drn | \
              droonga-send --server=192.168.200.254)
    % time (cat ~/wikipedia-search/config/groonga/indexes.grn | grn2drn | \
              droonga-send --server=192.168.200.254)
    % time (cat ~/wikipedia-search/data/groonga/ja-pages.grn | grn2drn | \
              droonga-send --server=192.168.200.254 \
                           --server=192.168.200.3 \
                           --server=192.168.200.4 \
                           --report-throughput \
                           --messages-per-second=50)

データベースの内容をダンプして直接流し込む場合も同様に、スキーマ定義とデータ投入で分散の有無を分ける必要がある。

    % time (grndump --no-dump-tables $HOME/groonga/db/db | grn2drn | \
              droonga-send --server=192.168.200.254 \
                           --report-throughput)
    % time (grndump --no-dump-schema --no-dump-indexes $HOME/groonga/db/db | \
              grn2drn | \
              droonga-send --server=192.168.200.254 \
                           --server=192.168.200.3 \
                           --server=192.168.200.4 \
                           --report-throughput \
                           --messages-per-second=50)

## ベンチマーク実行環境のセットアップ

192.168.200.2で行う。

    % sudo apt-get update
    % sudo apt-get -y upgrade
    % sudo apt-get install -y ruby curl
    % sudo gem install drnbench

ページのタイトルから、検索リクエストのパターンファイルを作成する。

    % base_params="table=Pages&limit=10&match_columns=title,text&output_columns=snippet_html(title),snippet_html(text),categories,_key"
    % curl "http://192.168.200.254:10041/d/select?table=Pages&limit=200&output_columns=title" | \
        drnbench-extract-searchterms | \
        drnbench-generate-select-patterns --base-params="$base_params" \
        > ./patterns-1node.json
    % curl "http://192.168.200.254:10041/d/select?table=Pages&limit=200&output_columns=title" | \
        drnbench-extract-searchterms | \
        drnbench-generate-select-patterns --base-params="$base_params" --hosts=192.168.200.254,192.168.200.3 \
        > ./patterns-2nodes.json
    % curl "http://192.168.200.254:10041/d/select?table=Pages&limit=200&output_columns=title" | \
        drnbench-extract-searchterms | \
        drnbench-generate-select-patterns --base-params="$base_params" --hosts=192.168.200.254,192.168.200.3,192.168.200.4 \
        > ./patterns-3nodes.json

patterns-2nodes.json, patterns-3nodes.jsonは、接続先をそれぞれのノードに等分に振り分けるようにした物。
droonga-engineやdroonga-http-serverのプロセスがボトルネックになっている場合はこれを使い、各ノードの性能を使い切るようにする。

クエリの件数は200件としている。
Groonga、Droonga共にデフォルトのキャッシュ件数は100件なので、200種類のリクエストがあると、理論上のキャッシュヒット率は50％程度になると考えられる。

## ベンチマークの実行

192.168.200.2で行う。

 * durationは、初期化と終了の時のばらつきを慣らすため長めにとる。ここでは30秒としている。

### Groongaのベンチマーク

    (on 192.168.200.254)
    % groonga -p 10041 -d --protocol http $HOME/groonga/db/db

    (on 192.168.200.2)
    % drnbench-request-response \
        --n-slow-requests=5 \
        --start-n-clients=0 \
        --end-n-clients=20 \
        --step=2 \
        --duration=30 \
        --wait=0.01 \
        --interval=10 \
        --mode=http \
        --request-patterns-file=$PWD/patterns-1node.json \
        --default-host=192.168.200.254 \
        --default-port=10041 \
        --output-path=$PWD/groonga-result.csv

    (on 192.168.200.254)
    % pkill groonga

### Droongaのベンチマーク

念のため、ベンチマークの取得の前後にはサーバを再起動しておく。

    (on 192.168.200.254, 192.168.200.3, 192.168.200.4)
    % kill $(cat ~/droonga/droonga-engine.pid)
    % kill $(cat ~/droonga/droonga-http-server.pid)
    % rm -rf ~/droonga/state
    % droonga-engine \
        --host=$host \
        --log-file=$DROONGA_BASE_DIR/droonga-engine.log \
        --daemon \
        --pid-file=$DROONGA_BASE_DIR/droonga-engine.pid
    % droonga-http-server \
        --port=10042 \
        --receive-host-name=$host \
        --droonga-engine-host-name=$host \
        --environment=production \
        --daemon \
        --pid-file=$DROONGA_BASE_DIR/droonga-http-server.pid

#### 1ノード（192.168.200.254）

    (on 192.168.200.254, 192.168.200.3, 192.168.200.4)
    % droonga-engine-catalog-modify \
        --source ~/droonga/catalog.json \
        --update \
        --remove-replica-hosts=192.168.200.3,192.168.200.4

    (on 192.168.200.2)
    % drnbench-request-response \
        --n-slow-requests=5 \
        --start-n-clients=0 \
        --end-n-clients=20 \
        --step=2 \
        --duration=30 \
        --wait=0.01 \
        --interval=10 \
        --mode=http \
        --request-patterns-file=$PWD/patterns-1node.json \
        --default-host=192.168.200.254 \
        --default-port=10042 \
        --output-path=$PWD/droonga-result-1node.csv

#### 2ノード（192.168.200.254, 192.168.200.3）

    (on 192.168.200.254, 192.168.200.3, 192.168.200.4)
    % droonga-engine-catalog-modify \
        --source ~/droonga/catalog.json \
        --update \
        --add-replica-hosts=192.168.200.3

    (on 192.168.200.2)
    % drnbench-request-response \
        --n-slow-requests=5 \
        --start-n-clients=0 \
        --end-n-clients=20 \
        --step=2 \
        --duration=30 \
        --wait=0.01 \
        --interval=10 \
        --mode=http \
        --request-patterns-file=$PWD/patterns-2nodes.json \
        --default-host=192.168.200.254 \
        --default-port=10042 \
        --output-path=$PWD/droonga-result-2nodes.csv

#### 3ノード（192.168.200.254, 192.168.200.3, 192.168.200.3）

    (on 192.168.200.254, 192.168.200.3, 192.168.200.4)
    % droonga-engine-catalog-modify \
        --source ~/droonga/catalog.json \
        --update \
        --add-replica-hosts=192.168.200.4

    (on 192.168.200.2)
    % drnbench-request-response \
        --n-slow-requests=5 \
        --start-n-clients=0 \
        --end-n-clients=20 \
        --step=2 \
        --duration=30 \
        --wait=0.01 \
        --interval=10 \
        --mode=http \
        --request-patterns-file=$PWD/patterns-3nodes.json \
        --default-host=192.168.200.254 \
        --default-port=10042 \
        --output-path=$PWD/droonga-result-3nodes.csv

