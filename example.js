var srcds = require('./main.js');

// If the example isn't working, it might just be that the server it's trying to query is down. You can cross check that here:
// http://www.gametracker.com/server_info/27.50.71.3:21015/
// If it is down, find a Team Fortress 2 server that isn't and change the IP and port accordingly

client = srcds('27.50.71.3', 21045);

client.info(function(err, info) {
  if (err) {
    console.error(err)
  }
  else {
    console.log(info);
  }
  client.player(function(err, players) {
    if (err) {
      console.error(err)
    }
    else {
        console.log(players);
    }
    client.close();
  });
});

