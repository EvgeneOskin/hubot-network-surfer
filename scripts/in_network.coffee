# Description:
#   Example scripts for you to examine and try out.
#
# Configuration:
#   SURFER_SUBNET_WITH_MASK - ip address with subnet mask, ie 192.168.1.0/24
#
# Commands:
#  ping when <user_id> come to office - send private message when user with <user_id> come to office
#
# Notes:
#   They are commented out by default, because most of them are pretty silly and
#   wouldn't be useful and amusing enough for day to day huboting.
#   Uncomment the ones you want to try and experiment with.

Promise = require "bluebird"
arp = Promise.promisifyAll require 'node-arp'
ping = Promise.promisifyAll require("net-ping")
IpSubnetCalculator = require 'ip-subnet-calculator'

class UserIDMACBinder
  constructor: (@robot) ->
    @key = 'local_network_macs'

  bind: (mac, userID) ->
    network_macs = @robot.brain.get(@key) or {}
    network_macs[mac] = userID
    @robot.brain.set @key, mac

  getByMAC: (mac) ->
    macs = @robot.brain.get(@key) or {}
    macs[mac]


class SubNetSurfer
  constructor: (@robot, @network, @subnet) ->
    @brainKey = 'live_macs'

  startSurf: () ->
    console.log('Start surfing')
    @network.mapIpWithMask(@subnet)
    .map (ip) =>
      @network.pingIP(ip).then () ->
        ip
      .catch(()->)
    .filter((ip) -> ip)
    .map (ip) =>
      @network.getMACByIP(ip)
      .then (mac) ->
        {ip: ip, mac: mac}
      .catch () ->
    .filter((ip_mac) -> ip_mac.mac isnt '(incomplete)')
    .map((ip_mac) -> ip_mac.mac)
    .then (live_macs) =>
      @updateMacs(live_macs)
      @robot.emit("macs_updated", @)
    .catch (err) =>
      console.log(err)
      @robot.emit("macs_updated", @)

  generateIp: (i) ->
    @subnet + i.toString()

  updateMacs: (live_macs) ->
    live_macs = new Set(live_macs)
    old_live_macs = @robot.brain.get(@brainKey) or new Set()
    old_live_macs.forEach (mac) =>
      @robot.emit("mac_down", mac) if not live_macs.has(mac)
    live_macs.forEach (mac) =>
      @robot.emit("mac_up", mac) if not old_live_macs.has(mac)
    @robot.brain.set @brainKey, live_macs


class Network

  pingSession = ping.createSession()

  getMACByIP: (ip) ->
    arp.getMACAsync ip

  pingIP: (ip) ->
    pingSession.pingHostAsync ip

  ipRange: (ipWithMask) ->
    [ip, mask] = ipWithMask.split('/')
    IpSubnetCalculator.calculateSubnetMask(ip, mask)

  mapIpWithMask: (ipWithMask) ->
    range = @ipRange(ipWithMask)
    Promise.map [range.ipLow..range.ipHigh], (ipDecimal) ->
      IpSubnetCalculator.toString(ipDecimal)


class Notifier

  brainKey = 'track_notifier'

  constructor: (@robot, @binder) ->

  track: (who, byWhom) ->
    key = @renderKey(who)
    trackers = @robot.brain.get(key) or new Set()
    trackers.add(byWhom)
    @robot.brain.set(key, trackers)
    console.log "#{byWhom} tracks #{Array.from(trackers)}"

  notifyTrackers: (mac) ->
    who = @binder.getByMAC(mac)
    if not who
      return
    key = @renderKey(who)
    trackers = @robot.brain.get(key, new Set())
    for i in trakers
      user = @robot.brain.userForId i
      @robot.send user, "#{who} come to office!"

  renderKey: (who) ->
    @brainKey + who

  getMessageUser: (res) ->
    res.message.user.id

  getRegistrationUser: (userID) ->
    user = @robot.brain.userForId userID
    userID if user


module.exports = (robot) ->

  surfCountDown = 1000
  subnet = process.env.SURFER_SUBNET_WITH_MASK
  binder = new UserIDMACBinder(robot)
  network = new Network()
  notifier = new Notifier(robot, binder)
  surfer = new SubNetSurfer(robot, network, subnet)
  surfer.startSurf()

  robot.on "mac_down", (mac) ->
    console.log "#{mac} down"

  robot.on "mac_up", (mac) ->
    console.log "#{mac} up"
    notifier.notifyTrackers mac

  robot.on "macs_updated", (surfer) ->
    setTimeout () ->
      surfer.startSurf()
    , surfCountDown

  robot.router.post '/hubot/in/network/register/', (req, res) ->
    data = if req.body.payload? then JSON.parse req.body.payload else req.body
    {user_id: userID, ip: ip} = data
    userID = notifier.getRegistrationUser(userID)
    if not (ip and user_id) or not userID
      res.send JSON.stringify
        error: 'ip or user_id missed or invalid user'
      return

    network.getMACByIP(ip).then (mac) ->
      if mac is '(incomplete)'
        console.log "Fail to register: ip #{ip}, user_id #{userID}"
        return
      binder.bind(mac, userID)
    res.send '{}'

  robot.respond /ping when (.*) come to office/i, (res) ->
    username = res.match[1]
    author = notifier.getMessageUser(res)
    user = notifier.getRegistrationUser(username)
    if user
      notifier.track user, author
    else
      res.reply 'No such user.'
