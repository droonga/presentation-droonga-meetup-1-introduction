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

Droongaのworkerは、1プロセスあたり最大でデータベースの大きさと同じだけのメモリを消費する。
例えばworker数4でデータベースサイズが2GiBなら、消費するメモリの量は最大で2×4＝8GiBとなる。

データベースサイズが実メモリの量より大きいと、スワップが発生して性能が低下する。
しかしデータベースサイズが小さすぎると、検索の処理が軽すぎてベンチマークを取りにくくなる。
よって、データベースサイズが実メモリをギリギリ使い切らない程度のサイズになるようにする必要がある。

 * Groongaではシングルプロセス・マルチスレッドのため、データベースの最大サイズは実メモリの量にほぼ等しい。
   それに対しDroongaでは、プロセスごとに別々にデータベースをメモリ上に保持するため、1プロセスあたりが使えるメモリの最大サイズ＝データベースの最大サイズは、Groongaよりも小さくなる。
   * 既にデータベースサイズがこの計算で求めた最大サイズを超えている場合には、worker数を減らす。
     worker数を減らせば、その分だけ各プロセスが使えるメモリの最大サイズが増える＝扱えるデータベースの最大サイズが増える。
 * 当然のことながら、実際に運用中のサービスがあるのであれば、データベースサイズは運用中のサービスのデータベースサイズと同等にすることが望ましい。

上記の検証環境では、ノードのうち2台が8GB、1台が6GBのメモリを積んでいる。
なので、6÷4＝1.5GB程度のデータベースサイズが適切と考えられる。

### データの準備

Wikipediaのデータを取得し、Groongaのダンプファイルに変換する。

    % cd ~/
    % git clone https://github.com/droonga/wikipedia-search.git
    % cd wikipedia-search
    % bundle install
    % time rake data:convert:groonga:ja

既定の状態では、Wikipedia日本語版の全ページのうち先頭5000件、各ページは先頭から1000文字までのみ変換される。
それ以上の件数を変換するには、以下の箇所で「--max-n-*」を指定しているコマンドラインオプションを変更する。
（正しいやり方が分かり次第、この説明を更新する。）

https://github.com/droonga/wikipedia-search/blob/master/lib/wikipedia-search/task.rb#L79

検証時には、184万件のページ全件をロードするとデータベースは17GiB程度になった。
大雑把に考えて、10万件で1GiBになる。
前述の計算から、データベースサイズは1.5GiB程度までに収める必要があるので、ロードするべきページの件数は15万件程度が妥当と言える。

検証環境では、15万件のデータの変換には12分程度を要した。


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

検証環境では、184万件全件のロードだと10時間程度を要した。
15万件のロードだと、24分を要した。

### HTTPサーバの起動

    % groonga -p 10041 -d --protocol http $HOME/groonga/db/db


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

    % time (cat ~/wikipedia-search/config/groonga/schema.grn | grn2drn | \
              droonga-send --server=192.168.200.254)
    % time (cat ~/wikipedia-search/config/groonga/indexes.grn | grn2drn | \
              droonga-send --server=192.168.200.254)
    % time (cat ~/wikipedia-search/data/groonga/ja-pages.grn | grn2drn | \
              droonga-send --server=192.168.200.254 \
                           --server=192.168.200.3 \
                           --server=192.168.200.4)

データベースの内容をダンプして直接流し込む場合も同様に、スキーマ定義とデータ投入で分散の有無を分ける必要がある。

    % time (grndump --no-dump-tables $HOME/groonga/db/db | grn2drn | \
              droonga-send --server=192.168.200.254 \
                           --report-throughput)
    % time (grndump --no-dump-schema --no-dump-indexes $HOME/groonga/db/db | \
              grn2drn | \
              droonga-send --server=192.168.200.254 \
                           --server=192.168.200.3 \
                           --server=192.168.200.4 \
                           --report-throughput)

検証環境では、15万件のロードだとXX分を要した。

## ベンチマーク実行環境のセットアップ

192.168.200.2で行う。

    % sudo apt-get update
    % sudo apt-get -y upgrade
    % sudo apt-get install -y ruby
    % sudo gem install drnbench

ページのタイトルから、検索リクエストのパターンファイルを作成する。

    % curl "http://192.168.200.254:10041/d/select?table=Pages&limit=1000&output_columns=title" | \
        ruby ./generate-patterns.rb \
        > ./patterns-1node.json
    % curl "http://192.168.200.254:10041/d/select?table=Pages&limit=1000&output_columns=title" | \
        ruby ./generate-patterns.rb 192.168.200.254,192.168.200.3 \
        > ./patterns-2nodes.json
    % curl "http://192.168.200.254:10041/d/select?table=Pages&limit=1000&output_columns=title" | \
        ruby ./generate-patterns.rb 192.168.200.254,192.168.200.3,192.168.200.4 \
        > ./patterns-3nodes.json

patterns-2nodes.json, patterns-3nodes.jsonは、接続先をそれぞれのノードに等分に振り分けるようにした物。
droonga-engineやdroonga-http-serverのプロセスがボトルネックになっている場合はこれを使い、各ノードの性能を使い切るようにする。

各パターンの最後に追加しているリクエストは、Webサービスのトップページから投げられるであろうリクエストに対応するものである。
これが全体の50％になるようにしてあり、リクエストの内容は固定なので、キャッシュヒット率は理論上は50％程度になるはず。

## ベンチマークの実行

192.168.200.2で行う。

### Groongaのベンチマーク

    % drnbench-request-response \
        --n-slow-requests=5 \
        --start-n-clients=0 \
        --end-n-clients=100 \
        --step=10 \
        --duration=10 \
        --wait=0.01 \
        --mode=http \
        --request-patterns-file=$PWD/patterns-1node.json \
        --default-host=192.168.200.254 \
        --default-port=10041 \
        --output-path=$PWD/groonga-result.csv

### Droongaのベンチマーク

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
        --end-n-clients=100 \
        --step=10 \
        --duration=10 \
        --wait=0.01 \
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
        --end-n-clients=100 \
        --step=10 \
        --duration=10 \
        --wait=0.01 \
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
        --end-n-clients=100 \
        --step=10 \
        --duration=10 \
        --wait=0.01 \
        --mode=http \
        --request-patterns-file=$PWD/patterns-3nodes.json \
        --default-host=192.168.200.254 \
        --default-port=10042 \
        --output-path=$PWD/droonga-result-3nodes.csv

