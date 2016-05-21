# Description:
#   Example scripts for you to examine and try out.
#
# Notes:
#   They are commented out by default, because most of them are pretty silly and
#   wouldn't be useful and amusing enough for day to day huboting.
#   Uncomment the ones you want to try and experiment with.

Promise = require "bluebird"
arp = Promise.promisifyAll require 'node-arp'

class MACBinder
  constructor: (@robot) ->
    @key = 'local_network_macs'

  bind: (mac, account) ->
    network_macs = @robot.brain.get(@key) or {}
    network_macs[mac] = account
    @robot.brain.set @key, mac

  getByMAC: (mac) ->
    @robot.brain.get(@key)[mac]


class SubNetSurfer
  constructor: (@robot) ->
    @schedulerId = null
    @countDown = 3*1000
    @brainKey = 'live_macs'
    @subnet = '192.168.1.'

  startSurf: () ->
    that = @
    clearTimeout(@schedulerId) if @schedulerId
    @schedulerId = setInterval () ->
      Promise.map [1..255], (i) ->
        that.subnet + i.toString()
      .mapSeries(i) ->
        arp.getMACAsync(i)
        .then (mac) -> total.add mac
        .catch () ->
      .filter (mac) ->
        console.log mac
        mac isnt '(incomplete)'
      .then (live_macs) ->
        that.updateMacs(live_macs)
        @robot.emit("macs_updated", that)
      .catch (err) ->
        console.log(err)
    , @countDown

  updateMacs: (live_macs) ->
    old_live_macs = @robot.brain.get @brainKey or new Set()
    old_live_macs.forEach (mac) ->
      @robot.emit("mac_down", mac) if not live_macs.has(mac)
    live_macs.forEach (mac) ->
      @robot.emit("mac_up", mac) if not old_live_macs.has(mac)
    @robot.brain.set @brainKey, live_macs


module.exports = (robot) ->

  binder = new MACBinder(robot)
  surfer = new SubNetSurfer(robot)
  surfer.startSurf()

  robot.on "mac_down", (mac) ->
    console.log "#{mac} down"

  robot.on "mac_up", (mac) ->
    console.log "#{mac} up"

  robot.on "mac_updated", (surfer) ->
    surfer.startSurf()

  robot.router.post '/hubot/in/network/register/', (req, res) ->
    data = if req.body.payload? then JSON.parse req.body.payload else req.body
    {account: account, ip: ip} = data

    if not (ip and account)
      res.send JSON.stringify
        error: 'ip or account missed'
      return

    arp.getMACAsync(ip).then (mac) ->
      if mac is '(incomplete)'
        console.log "Fail to register: ip #{ip}, account #{account}"
        return
      binder.bind(mac, account)
    res.send '{}'
