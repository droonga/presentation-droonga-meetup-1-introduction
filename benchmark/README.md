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


## 準備

あらかじめ、Wikipediaのデータを取得しておく。

    % cd ~/
    % git clone https://github.com/droonga/wikipedia-search.git
    % cd wikipedia-search
    % bundle install
    % rake data:convert:groonga:ja

既定の状態では、Wikipedia日本語版の全ページのうち先頭5000件、各ページは先頭から1000文字までのみ変換される。
Wikipeida日本語版の全ページ・全内容を変換するには、以下の箇所で「--max-n-*」を指定しているコマンドラインオプションをコメントアウトする。
（正しいやり方が分かり次第、この説明を更新する。）

https://github.com/droonga/wikipedia-search/blob/master/lib/wikipedia-search/task.rb#L79

## Groongaのセットアップ

192.168.200.254でのみ行う。

### インストール

    % sudo apt-get -y install software-properties-common
    % sudo add-apt-repository -y universe
    % sudo add-apt-repository -y ppa:groonga/ppa
    % sudo apt-get update
    % sudo apt-get -y install groonga

### データベースの用意

    % mkdir -p $HOME/groonga/db/
    % groonga -n $HOME/groonga/db/db quit
    % time (cat ~/wikipedia-search/config/groonga/schema.grn | groonga $HOME/groonga/db/db)
    % time (cat ~/wikipedia-search/config/groonga/indexes.grn | groonga $HOME/groonga/db/db)
    % time (cat ~/wikipedia-search/data/groonga/ja-pages.grn | groonga $HOME/groonga/db/db)

検証環境ではこのくらいの時間がかかった。

    [[0,1406253871.65481,38379.038287878],1840587]
    
    real    640m9.076s
    user    149m33.176s
    sys     4m38.246s


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
    % mkdir ~/droonga
    % droonga-engine-catalog-generate \
        --hosts=192.168.200.254,192.168.200.3,192.168.200.4 \
        --output=~/droonga/catalog.json

workerの数は以下の方法で調べた物を設定する（既定値は4）。

    % cat /proc/cpuinfo | grep processor

### サーバの起動

    (on 192.168.200.254)
    % export host=192.168.200.254
    % export DROONGA_BASE_DIR=$HOME/droonga
    % droonga-engine --host=$host \
                 --log-file=$DROONGA_BASE_DIR/droonga-engine.log \
                 --daemon \
                 --pid-file=$DROONGA_BASE_DIR/droonga-engine.pid
    % env NODE_ENV=production \
        droonga-http-server --port=10042 \
                        --receive-host-name=$host \
                        --droonga-engine-host-name=$host \
                        --daemon \
                        --pid-file=$DROONGA_BASE_DIR/droonga-http-server.pid

    (on 192.168.200.3)
    % export host=192.168.200.3
    ...

    (on 192.168.200.4)
    % export host=192.168.200.4
    ...

### データベースの用意

    % time (cat ~/wikipedia-search/config/groonga/schema.grn | \
              grn2drn | droonga-request --host 192.168.200.254 --port 10031)
    % time (cat ~/wikipedia-search/config/groonga/indexes.grn | \
              grn2drn | droonga-request --host 192.168.200.254 --port 10031)
    % time (cat ~/wikipedia-search/data/groonga/ja-pages.grn | \
              grn2drn | droonga-request --host 192.168.200.254 --port 10031)

または

    % time (grndump $HOME/groonga/db/db | grn2drn | \
              droonga-request --host 192.168.200.254 --port 10031)

## ベンチマーク実行環境のセットアップ

192.168.200.2で行う。

    % sudo apt-get update
    % sudo apt-get -y upgrade
    % sudo apt-get install -y ruby
    % sudo gem install drnbench

[よく検索されるページの一覧](http://stats.grok.se/ja/top)から、検索リクエストのパターンファイルを作成する。

    % echo '{"wikiledia-ja-search-with-query":{"frequency":0.5,"method":"get","patterns":[' \
        > patterns.json
    % curl 'http://stats.grok.se/ja/top' | grep "a href" | \
        sed -r -e 's/\&[^;]+;//g' \
               -e 's/[:;]/ /g' \
               -e 's;.+>([^<]+)</a>.*;{"path":"/d/select?query=\1\&table=Pages\&limit=50\&match_columns=title,text\&output_columns=snippet_html(title),snippet_html(text),categories,_key\&drilldown=categories\&drilldown_limits=50\&drilldown_sortby=-_nsubrecs"},;' \
               -e 's/ /%20/g' \
        >> patterns.json
    % echo '{"path":"/d/select?table=Pages&limit=10"}]},"wikiledia-ja-search":{"frequency":0.5,"method":"get","patterns":[{"path":"/d/select?table=Pages&limit=50&output_columns=title,categories,_key&drilldown=categories&drilldown_limits=50&drilldown_sortby=-_nsubrecs"}]}}' \
        >> patterns.json

patterns-2nodes.json, patterns-3nodes.jsonは、これを元に、接続先をそれぞれのノードに等分に振り分けるようにした物。
droonga-engineやdroonga-http-serverのプロセスがボトルネックになっている場合はこれを使い、各ノードの性能を使い切るようにする。

最後の行で追加しているリクエストは、Webサービスのトップページから投げられるであろうリクエストに対応するものである。
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

