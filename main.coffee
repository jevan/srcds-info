dgram = require "dgram"
packet = require "packet"
EventEmitter = require('events').EventEmitter

PACKETS = 
  info: new Buffer [
    "0xff", "0xff", "0xff", "0xff", "0x54", "0x53", "0x6f", "0x75",
    "0x72", "0x63", "0x65", "0x20", "0x45", "0x6e", "0x67", "0x69",
    "0x6e", "0x65", "0x20", "0x51", "0x75", "0x65", "0x72", "0x79", "0x00"
  ]
  playerChallenge: new Buffer ["0xff", "0xff", "0xff", "0xff", "0x55", "0xff", "0xff", "0xff", "0xff"]

RESPONSES =
  header: "x32, b8|chr() => type"
  info: """
    b8 => version,
    b8z|utf8() => serverName,
    b8z|utf8() => map,
    b8z|utf8() => gameType,
    b8z|utf8() => gameName,
    l16 => appID,
    b8 => numPlayers,
    b8 => maxPlayers,
    b8 => numBots,
    b8|chr() => dedicated,
    b8|chr() => os,
    b8 => password,
    b8 => secure,
    b8z|utf8() => gameVersion
  """
  challenge: "-l32 => challenge "
  playerStart: "b8 => numPlayers"
  player: """
    b8 => index,
    b8z|utf8() => name,
    -l32 => score,
    b32f => duration
  """ 

class SrcDS extends EventEmitter
  constructor: (ip, port, options={}) ->
    return new SrcDS(ip, port, options) if this is global
    [@ip, @port, @options] = [ip, port, options]

    @client = dgram.createSocket 'udp4'
    @parser = new packet.Parser()
    @parser._transforms.chr = (parsing, field, value) -> if parsing then String.fromCharCode(value) else value.charCodeAt()
    @client.on 'message', (msg, rinfo) =>
      @ip = rinfo.address
      @port = rinfo.port
      @parser.extract RESPONSES.header, (msg) =>
        @onMsg msg
      @parser.parse msg

    @options.timeout ||= 10000


  send: (packet, cb=->) ->
    @client.send packet, 0, packet.length, @port, @ip, (err) =>
      if err 
        cb err
      else
        #This is a bit crap - should figue out a way of matching responses to requests or queueing
        timeout = null
        msgcb = (msg) ->
          clearTimeout timeout
          cb null, msg
        
        @once 'message', msgcb
        
        timeout = setTimeout =>
          @removeListener 'message', msgcb
          cb new Error "Request timed out"
        , @options.timeout

  info: (cb) -> @send PACKETS.info, cb

  player: (cb) -> @send PACKETS.playerChallenge, cb

  onMsg: (msg) =>
    if msg.type == 'I'
      @parser.extract RESPONSES.info, (msg) =>
        @onInfo msg
    else if msg.type == 'D'
      @parser.extract RESPONSES.playerStart, (msg) =>
        @onPlayerStart msg
    else if msg.type == 'A'
      @parser.extract RESPONSES.challenge, (msg) =>
        @onChallenge msg
    
  onChallenge: (msg) =>
    playerQuery = new Buffer(9)
    PACKETS.playerChallenge.copy(playerQuery,0,0,5)
    playerQuery.writeInt32LE(msg.challenge,5)
    @client.send playerQuery, 0, playerQuery.length, @port, @ip

  onPlayerStart: (msg) =>
    if msg.numPlayers > 0 
      @parser.extract RESPONSES.player, (next_msg) =>
        @onPlayer next_msg, 1, msg.numPlayers, []
    else
      @emit "message", {ip: @ip, port: @port, numPlayers: msg.numPlayers, players: []} 

  onPlayer: (msg,cur,max,players) =>
    players.push(msg)
    if cur >= max
      @emit "message", {ip: @ip, port: @port, numPlayers: max, players: players}
    else
      @parser.extract RESPONSES.player, (msg) =>
        @onPlayer msg, cur+1, max, players

  onInfo: (msg) =>
    decoded = msg
    decoded.ip = @ip
    decoded.port = @port
    # Pretty things up a little
    switch decoded.os
      when "l"
        decoded.os = "Linux"
      when "w"
        decoded.os = "Windows"
    switch decoded.dedicated
      when "d"
        decoded.dedicated = "dedicated"
      when "l"
        decoded.dedicated = "listen"
      when "p"
        decoded.dedicated = "SourceTV"
    decoded.pw = (decoded.pw is 1)
    decoded.secure = (decoded.secure is 1)
    @emit "message", decoded

  close: ->
    @client.close()

module.exports = SrcDS
