(function() {
  toshi = {
    url: window.location.href.replace('http', 'ws'),
    connection: null,
    init: function() {
      this.createwebsocket();

      toshi.getStatus();
      window.setInterval(function(){
        toshi.getStatus();
      }, 5000);
    },
    createwebsocket: function() {
      this.connection = new WebSocket(this.url);
      this.connection.onopen = this.onopen;
      this.connection.onclose = this.onclose;
      this.connection.onerror = this.onerror;
      this.connection.onmessage = this.onmessage;
    },
    onopen: function() {
      console.log('Websocket connected');

      clearInterval(window.ping_websocket_server);
      window.ping_websocket_server = setInterval(function() {
        if (toshi.connection.bufferedAmount == 0)
          toshi.connection.send("Keep alive from client");
      }, 30000);

      toshi.connection.send(JSON.stringify({ subscribe: 'blocks' }));
      toshi.connection.send(JSON.stringify({ subscribe: 'transactions' }));
    },
    onclose: function(){
      console.log('Websocket connection closed');
      toshi.reconnectwebsocket();
    },
    onerror: function(error){
      console.log('Websocket error detected');
    },
    onmessage: function(e) {
      var obj = JSON.parse(e.data);

      if(obj.subscription === 'blocks') {
        toshi.onblock(obj.data);
      }

      if(obj.subscription === 'transactions') {
        toshi.ontransaction(obj.data);
      }
    },
    reconnectwebsocket: function() {
      setTimeout(function () {
        // Connection has closed so try to reconnect every 5 seconds.
        console.log('Trying to reconnect websocket...');
        toshi.createwebsocket();
      }, 5*1000);
    },
    onblock: function(obj) {
      var source   = $("#block-template").html();
      var template = Handlebars.compile(source);
      var context = {
        hash: obj.hash,
        height: obj.height,
        num_tx: obj.transactions_count,
        timestamp: moment.utc(obj.time).format('YYYY-MM-DD HH:mm:ss UTC'),
        created_at: moment.utc(obj.created_at).format('YYYY-MM-DD HH:mm:ss UTC'),
      }
      $(".stats_block").prepend(template(context));
      $('.stats_block .block:gt(5)').remove();
    },
    ontransaction: function(obj) {
      var source   = $("#tx-template").html();
      var template = Handlebars.compile(source);
      var context = {
        hash: obj.hash,
        size: obj.size,
        amount: obj.amount > 0 ? (obj.amount / 1e8).toFixed(8) : false,
        created_at: moment.utc(obj.created_at).format('YYYY-MM-DD HH:mm:ss UTC'),
        pool: obj.pool,
      }
      $(".stats_tx").prepend(template(context));
      $('.stats_tx .tx:gt(5)').remove();
    },
    changeStatus: function(status) {
      if(typeof status === 'undefined') {
        status = 'offline'
      }

      $('.websocket_stats').hide();
      $('.websocket_stats.' + status).show()
    },
    getStatus: function() {
      $.getJSON("/api/toshi.json")
        .done(function(data) {
          $('.available-peers').html(data.peers.available);
          $('.connected-peers').html(data.peers.connected);
          $('.database-size').html(data.database.size);
          $('.tx-count').html(pretty_number(data.transactions.count));
          $('.unconfirmed-tx-count').html(pretty_number(data.transactions.unconfirmed_count));
          $('.blocks-count').html(pretty_number(data.blocks.main_count));
          $('.side-blocks-count').html(pretty_number(data.blocks.side_count));
          $('.orphan-blocks-count').html(pretty_number(data.blocks.orphan_count));
          toshi.changeStatus(data.status);
        })
        .fail(function( jqxhr, textStatus, error ) {
          toshi.changeStatus('offline');
        });
    }
  };
}());