# Description:
#   Example scripts for you to examine and try out.
#
# Notes:
#   They are commented out by default, because most of them are pretty silly and
#   wouldn't be useful and amusing enough for day to day huboting.
#   Uncomment the ones you want to try and experiment with.

Promise = require "bluebird"
arp = Promise.promisifyAll require 'node-arp'

class AccountMACBinder
  constructor: (@robot) ->
    @key = 'local_network_macs'

  bind: (mac, account) ->
    network_macs = @robot.brain.get(@key) or {}
    network_macs[mac] = account
    @robot.brain.set @key, mac

  getByMAC: (mac) ->
    @robot.brain.get(@key)[mac]


class SubNetSurfer
  constructor: (@robot, @network) ->
    @brainKey = 'live_macs'
    @subnet = '192.168.1.'

  startSurf: () ->
    console.log('Start surfing')
    Promise.map [1..255], (i) =>
      @generateIp(i)
    .map (i) =>
      @network.getMACByIP(i)
      .then (mac) ->
        mac
      .catch () ->
    .filter (mac) ->
      mac isnt '(incomplete)'
    .then (live_macs) =>
      @updateMacs(live_macs)
      @robot.emit("macs_updated", @)
    .catch (err) =>
      console.log(err)
      @robot.emit("macs_updated", @)

  generateIp: (i) ->
    @subnet + i.toString()

  updateMacs: (live_macs) ->
    live_macs = live_macs or new Set()
    old_live_macs = @robot.brain.get(@brainKey) or new Set()
    old_live_macs.forEach (mac) =>
      @robot.emit("mac_down", mac) if not live_macs.has(mac)
    live_macs.forEach (mac) =>
      @robot.emit("mac_up", mac) if not old_live_macs.has(mac)
    @robot.brain.set @brainKey, live_macs


class Network
  getMACByIP: (ip) ->
    arp.getMACAsync(ip)


module.exports = (robot) ->

  binder = new AccountMACBinder(robot)
  network = new Network()
  surfer = new SubNetSurfer(robot, network)
  surfer.startSurf()
  surfCountDown = 1000

  robot.on "mac_down", (mac) ->
    console.log "#{mac} down"

  robot.on "mac_up", (mac) ->
    console.log "#{mac} up"

  robot.on "macs_updated", (surfer) ->
    setTimeout () ->
      surfer.startSurf()
    , surfCountDown

  robot.router.post '/hubot/in/network/register/', (req, res) ->
    data = if req.body.payload? then JSON.parse req.body.payload else req.body
    {account: account, ip: ip} = data

    if not (ip and account)
      res.send JSON.stringify
        error: 'ip or account missed'
      return

    network.getMACByIP(ip).then (mac) ->
      if mac is '(incomplete)'
        console.log "Fail to register: ip #{ip}, account #{account}"
        return
      binder.bind(mac, account)
    res.send '{}'
